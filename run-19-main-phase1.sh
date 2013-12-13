#!/bin/bash

# This is not necessarily the top-level run.sh as it is in other directories.   see README.txt first.

[ ! -f ./lang.conf ] && echo "Language configuration does not exist! Use the configurations in conf/lang/* as a startup" && exit 1
[ ! -f ./conf/common_vars.sh ] && echo "the file conf/common_vars.sh does not exist!" && exit 1

. conf/common_vars.sh || exit 1;
. ./lang.conf || exit 1;

[ -f local.conf ] && . ./local.conf

set -e           #Exit on non-zero return code from any command
set -o pipefail  #Exit if any of the commands in the pipeline will 
                 #return non-zero return code
#set -u           #Fail on an undefined variable

share_silence_phones=true
data_only=false

type=train
skip_kws=true
skip_stt=false
max_states=150000
wip=0.5
segmentation_opts="--remove-noise-only-segments true --max-length-diff 0.4 --min-inter-utt-silence-length 1.0" 
silence_segment_fraction=1.0
keep_silence_segments=false
remove_oov=false
keep_fillers=true # If true, prepare the STM file keeping the fillers in it. This is typically used while decoding the training data for retranscription
score_intermediate=

. ./path.sh
. utils/parse_options.sh

mkdir -p data

#Preparing dev2h and train directories
if [ ! -d data/raw_train_data ]; then
    echo ---------------------------------------------------------------------
    echo "Subsetting the TRAIN set"
    echo ---------------------------------------------------------------------

    local/make_corpus_subset.sh "$train_data_dir" "$train_data_list" ./data/raw_train_data
    train_data_dir=`readlink -f ./data/raw_train_data`

    nj_max=`cat $train_data_list | wc -l`
    if [[ "$nj_max" -lt "$train_nj" ]] ; then
        echo "The maximum reasonable number of jobs is $nj_max (you have $train_nj)! (The training and decoding process has file-granularity)"
        exit 1;
        train_nj=$nj_max
    fi
fi
train_data_dir=`readlink -f ./data/raw_train_data`

if [ ! -d data/raw_dev2h_data ]; then
  echo ---------------------------------------------------------------------
  echo "Subsetting the DEV2H set"
  echo ---------------------------------------------------------------------  
  local/make_corpus_subset.sh "$dev2h_data_dir" "$dev2h_data_list" ./data/raw_dev2h_data || exit 1
fi

if [ ! -d data/raw_dev10h_data ]; then
  echo ---------------------------------------------------------------------
  echo "Subsetting the DEV10H set"
  echo ---------------------------------------------------------------------  
  local/make_corpus_subset.sh "$dev10h_data_dir" "$dev10h_data_list" ./data/raw_dev10h_data || exit 1
fi

decode_nj=$dev2h_nj
nj_max=`cat $dev2h_data_list | wc -l`
if [[ "$nj_max" -lt "$decode_nj" ]] ; then
  echo "The maximum reasonable number of jobs is $nj_max -- you have $decode_nj! (The training and decoding process has file-granularity)"
  exit 1
  decode_nj=$nj_max
fi

mkdir -p data/local
if [[ ! -f data/local/lexicon.txt || data/local/lexicon.txt -ot "$lexicon_file" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing lexicon in data/local on" `date`
  echo ---------------------------------------------------------------------
  local/prepare_lexicon_separate_fillers.pl  --phonemap "$phoneme_mapping" \
    $lexiconFlags $lexicon_file data/local
fi

if [[ ! -f data/train/wav.scp || data/train/wav.scp -ot "$train_data_dir" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing acoustic training lists in data/train on" `date`
  echo ---------------------------------------------------------------------
  mkdir -p data/train
  local/prepare_acoustic_training_data_separate_fillers.pl \
    --vocab data/local/lexicon.txt --fragmentMarkers \-\*\~ \
    $train_data_dir data/train > data/train/skipped_utts.log
  mv data/train/text data/train/text_orig
  cat data/train/text_orig | sed 's/<silence>\ //g' | sed 's/\ <silence>//g' > data/train/text
  cat data/train/text | tr ' ' '\n' | \
    sed -n '/<.*>/p' | sed '/'$oovSymbol'/d' | \
    sort -u > data/local/fillers.list
  rm data/local/lexicon.txt
fi

if [[ ! -f data/local/lexicon.txt || data/local/lexicon.txt -ot "$lexicon_file" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing lexicon with all fillers in data/local on" `date`
  echo ---------------------------------------------------------------------
  local/prepare_lexicon_separate_fillers.pl  --add data/local/fillers.list --phonemap "$phoneme_mapping" \
    $lexiconFlags $lexicon_file data/local
fi

mkdir -p data/lang
if [[ ! -f data/lang/L.fst || data/lang/L.fst -ot data/local/lexicon.txt ]]; then
  echo ---------------------------------------------------------------------
  echo "Creating L.fst etc in data/lang on" `date`
  echo ---------------------------------------------------------------------
  utils/prepare_lang.sh \
    --share-silence-phones $share_silence_phones \
    data/local $oovSymbol data/local/tmp.lang data/lang
fi


if [[ ! -f data/train/glm || data/train/glm -ot "$glmFile" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing train stm files in data/train on" `date`
  echo ---------------------------------------------------------------------
  local/prepare_stm.pl --fragmentMarkers \-\*\~ data/train || exit 1
fi

if [[ ! -f data/dev2h/wav.scp || data/dev2h/wav.scp -ot ./data/raw_dev2h_data/audio ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing dev2h data lists in data/dev2h on" `date`
  echo ---------------------------------------------------------------------
  mkdir -p data/dev2h
  local/prepare_acoustic_training_data_separate_fillers.pl \
    --fragmentMarkers \-\*\~ \
    `pwd`/data/raw_dev2h_data data/dev2h > data/dev2h/skipped_utts.log || exit 1
fi

if [[ ! -f data/dev2h/glm || data/dev2h/glm -ot "$glmFile" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing dev2h stm files in data/dev2h on" `date`
  echo ---------------------------------------------------------------------
  if [ -z $stm_file ]; then 
    echo "WARNING: You should define the variable stm_file pointing to the IndusDB stm"
    echo "WARNING: Doing that, it will give you scoring close to the NIST scoring.    "
    local/prepare_stm.pl --fragmentMarkers \-\*\~ data/dev2h || exit 1
  else
    local/augment_original_stm.pl $stm_file data/dev2h || exit 1
  fi
  [ ! -z $glmFile ] && cp $glmFile data/dev2h/glm

fi

# We will simply override the default G.fst by the G.fst generated using SRILM
if [[ ! -f data/srilm/lm.gz || data/srilm/lm.gz -ot data/train/text ]]; then
  echo ---------------------------------------------------------------------
  echo "Training SRILM language models on" `date`
  echo ---------------------------------------------------------------------
  local/train_lms_srilm.sh --dev-text data/dev2h/text \
    --train-text data/train/text data data/srilm 
fi
if [[ ! -f data/lang/G.fst || data/lang/G.fst -ot data/srilm/lm.gz ]]; then
  echo ---------------------------------------------------------------------
  echo "Creating G.fst on " `date`
  echo ---------------------------------------------------------------------
  local/arpa2G.sh data/srilm/lm.gz data/lang data/lang
fi
  
echo ---------------------------------------------------------------------
echo "Starting plp feature extraction for data/train in plp on" `date`
echo ---------------------------------------------------------------------

use_pitch=false
use_ffv=false

if [ ! -f data/train/.plp.done ]; then
  if [ "$use_pitch" = "false" ] && [ "$use_ffv" = "false" ]; then
   steps/make_plp.sh --cmd "$train_cmd" --nj $train_nj data/train exp/make_plp/train plp
  elif [ "$use_pitch" = "true" ] && [ "$use_ffv" = "true" ]; then
    cp -rT data/train data/train_plp; cp -rT data/train data/train_pitch; cp -rT data/train data/train_ffv
    steps/make_plp.sh --cmd "$train_cmd" --nj $train_nj data/train_plp exp/make_plp/train plp_tmp_train
    local/make_pitch.sh --cmd "$train_cmd" --nj $train_nj data/train_pitch exp/make_pitch/train pitch_tmp_train
    local/make_ffv.sh --cmd "$train_cmd"  --nj $train_nj data/train_ffv exp/make_ffv/train ffv_tmp_train
    steps/append_feats.sh --cmd "$train_cmd" --nj $train_nj data/train{_plp,_pitch,_plp_pitch} exp/make_pitch/append_train_pitch plp_tmp_train
    steps/append_feats.sh --cmd "$train_cmd" --nj $train_nj data/train{_plp_pitch,_ffv,} exp/make_ffv/append_train_pitch_ffv plp
    rm -rf {plp,pitch,ffv}_tmp_train data/train_{plp,pitch,plp_pitch}
  elif [ "$use_pitch" = "true" ]; then
    cp -rT data/train data/train_plp; cp -rT data/train data/train_pitch
    steps/make_plp.sh --cmd "$train_cmd" --nj $train_nj data/train_plp exp/make_plp/train plp_tmp_train
    local/make_pitch.sh --cmd "$train_cmd" --nj $train_nj data/train_pitch exp/make_pitch/train pitch_tmp_train
    steps/append_feats.sh --cmd "$train_cmd" --nj $train_nj data/train{_plp,_pitch,} exp/make_pitch/append_train plp
    rm -rf {plp,pitch}_tmp_train data/train_{plp,pitch}
  elif [ "$use_ffv" = "true" ]; then
    cp -rT data/train data/train_plp; cp -rT data/train data/train_ffv
    steps/make_plp.sh --cmd "$train_cmd" --nj $train_nj data/train_plp exp/make_plp/train plp_tmp_train
    local/make_ffv.sh --cmd "$train_cmd" --nj $train_nj data/train_ffv exp/make_ffv/train ffv_tmp_train
    steps/append_feats.sh --cmd "$train_cmd" --nj $train_nj data/train{_plp,_ffv,} exp/make_ffv/append_train plp
    rm -rf {plp,ffv}_tmp_train data/train_{plp,ffv}
  fi

  steps/compute_cmvn_stats.sh \
    data/train exp/make_plp/train plp
  # In case plp or pitch extraction failed on some utterances, delist them
  utils/fix_data_dir.sh data/train
  touch data/train/.plp.done
fi

if [ ! -f data/train_sub3/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Subsetting monophone training data in data/train_sub[123] on" `date`
  echo ---------------------------------------------------------------------
  numutt=`cat data/train/feats.scp | wc -l`;
  utils/subset_data_dir.sh data/train  5000 data/train_sub1
  if [ $numutt -gt 10000 ] ; then
    utils/subset_data_dir.sh data/train 10000 data/train_sub2
  else
    (cd data; ln -s train train_sub2 )
  fi
  if [ $numutt -gt 20000 ] ; then
    utils/subset_data_dir.sh data/train 20000 data/train_sub3
  else
    (cd data; ln -s train train_sub3 )
  fi

  touch data/train_sub3/.done
fi

if $data_only; then
  echo "Data preparation done !"
  exit 0
fi

if [ ! -f exp/mono/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting (small) monophone training in exp/mono on" `date`
  echo ---------------------------------------------------------------------
  steps/train_mono.sh \
    --boost-silence $boost_sil --nj 8 --cmd "$train_cmd" \
    data/train_sub1 data/lang exp/mono
  touch exp/mono/.done
fi

if [ ! -f exp/tri1/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting (small) triphone training in exp/tri1 on" `date`
  echo ---------------------------------------------------------------------
  steps/align_si.sh \
    --boost-silence $boost_sil --nj 12 --cmd "$train_cmd" \
    data/train_sub2 data/lang exp/mono exp/mono_ali_sub2
  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" $numLeavesTri1 $numGaussTri1 \
    data/train_sub2 data/lang exp/mono_ali_sub2 exp/tri1
  touch exp/tri1/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (medium) triphone training in exp/tri2 on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/tri2/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj 24 --cmd "$train_cmd" \
    data/train_sub3 data/lang exp/tri1 exp/tri1_ali_sub3
  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" $numLeavesTri2 $numGaussTri2 \
    data/train_sub3 data/lang exp/tri1_ali_sub3 exp/tri2
  touch exp/tri2/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (full) triphone training in exp/tri3 on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/tri3/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train data/lang exp/tri2 exp/tri2_ali
  steps/train_deltas.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesTri3 $numGaussTri3 data/train data/lang exp/tri2_ali exp/tri3
  touch exp/tri3/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (lda_mllt) triphone training in exp/tri4 on" `date`
echo ---------------------------------------------------------------------
if [ ! -f exp/tri4/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train data/lang exp/tri3 exp/tri3_ali
  steps/train_lda_mllt.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesMLLT $numGaussMLLT data/train data/lang exp/tri3_ali exp/tri4
  touch exp/tri4/.done
fi

echo ---------------------------------------------------------------------
echo "Starting (SAT) triphone training in exp/tri5 on" `date`
echo ---------------------------------------------------------------------

if [ ! -f exp/tri5/.done ]; then
  steps/align_si.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train data/lang exp/tri4 exp/tri4_ali
  steps/train_sat.sh \
    --boost-silence $boost_sil --cmd "$train_cmd" \
    $numLeavesSAT $numGaussSAT data/train data/lang exp/tri4_ali exp/tri5
  touch exp/tri5/.done
fi

if [ ! -f exp/tri5_ali/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Starting exp/tri5_ali on" `date`
  echo ---------------------------------------------------------------------
  steps/align_fmllr.sh \
    --boost-silence $boost_sil --nj $train_nj --cmd "$train_cmd" \
    data/train data/lang exp/tri5 exp/tri5_ali
  touch exp/tri5_ali/.done
fi

function make_plp {
  t=$1
  use_pitch=false
  use_ffv=false

  if [ "$use_pitch" = "false" ] && [ "$use_ffv" = "false" ]; then
   steps/make_plp.sh --cmd "$decode_cmd" --nj $my_nj data/${t} exp/make_plp/${t} plp
  elif [ "$use_pitch" = "true" ] && [ "$use_ffv" = "true" ]; then
    cp -rT data/${t} data/${t}_plp; cp -rT data/${t} data/${t}_pitch; cp -rT data/${t} data/${t}_ffv
    steps/make_plp.sh --cmd "$decode_cmd" --nj $my_nj data/${t}_plp exp/make_plp/${t} plp_tmp_${t}
    local/make_pitch.sh --cmd "$decode_cmd" --nj $my_nj data/${t}_pitch exp/make_pitch/${t} pitch_tmp_${t}
    local/make_ffv.sh --cmd "$decode_cmd"  --nj $my_nj data/${t}_ffv exp/make_ffv/${t} ffv_tmp_${t}
    steps/append_feats.sh --cmd "$decode_cmd" --nj $my_nj data/${t}{_plp,_pitch,_plp_pitch} exp/make_pitch/append_${t}_pitch plp_tmp_${t}
    steps/append_feats.sh --cmd "$decode_cmd" --nj $my_nj data/${t}{_plp_pitch,_ffv,} exp/make_ffv/append_${t}_pitch_ffv plp
    rm -rf {plp,pitch,ffv}_tmp_${t} data/${t}_{plp,pitch,plp_pitch}
  elif [ "$use_pitch" = "true" ]; then
    cp -rT data/${t} data/${t}_plp; cp -rT data/${t} data/${t}_pitch
    steps/make_plp.sh --cmd "$decode_cmd" --nj $my_nj data/${t}_plp exp/make_plp/${t} plp_tmp_${t}
    local/make_pitch.sh --cmd "$decode_cmd" --nj $my_nj data/${t}_pitch exp/make_pitch/${t} pitch_tmp_${t}
    steps/append_feats.sh --cmd "$decode_cmd" --nj $my_nj data/${t}{_plp,_pitch,} exp/make_pitch/append_${t} plp
    rm -rf {plp,pitch}_tmp_${t} data/${t}_{plp,pitch}
  elif [ "$use_ffv" = "true" ]; then
    cp -rT data/${t} data/${t}_plp; cp -rT data/${t} data/${t}_ffv
    steps/make_plp.sh --cmd "$decode_cmd" --nj $my_nj data/${t}_plp exp/make_plp/${t} plp_tmp_${t}
    local/make_ffv.sh --cmd "$decode_cmd" --nj $my_nj data/${t}_ffv exp/make_ffv/${t} ffv_tmp_${t}
    steps/append_feats.sh --cmd "$decode_cmd" --nj $my_nj data/${t}{_plp,_ffv,} exp/make_ffv/append_${t} plp
    rm -rf {plp,ffv}_tmp_${t} data/${t}_{plp,ffv}
  fi

  steps/compute_cmvn_stats.sh data/${t} exp/make_plp/${t} plp
  utils/fix_data_dir.sh data/${t}
}

if [ ${type} == shadow ] ; then
  mandatory_variables=""
  optional_variables=""
else
  mandatory_variables="${type}_data_dir ${type}_data_list ${type}_stm_file \
    ${type}_ecf_file ${type}_kwlist_file ${type}_rttm_file ${type}_nj"
  optional_variables="${type}_subset_ecf "
fi

eval my_data_dir=\$${type}_data_dir
eval my_data_list=\$${type}_data_list
eval my_stm_file=\$${type}_stm_file


eval my_ecf_file=\$${type}_ecf_file 
eval my_subset_ecf=\$${type}_subset_ecf 
eval my_kwlist_file=\$${type}_kwlist_file 
eval my_rttm_file=\$${type}_rttm_file
eval my_nj=\$${type}_nj  #for shadow, this will be re-set when appropriate

for variable in $mandatory_variables ; do
  eval my_variable=\$${variable}
  if [ $type != "train" ] && [ -z $my_variable ] ; then
    echo "Mandatory variable $variable is not set! " \
         "You should probably set the variable in the config file "
    exit 1
  else
    echo "$variable=$my_variable"
  fi
done

for variable in $option_variables ; do
  eval my_variable=\$${variable}
  echo "$variable=$my_variable"
done

datadir=data/train
dirid=train

nj_max=`cat $train_data_list | wc -l`
if [[ "$nj_max" -lt "$train_nj" ]] ; then
  echo "The maximum reasonable number of jobs is $nj_max (you have $train_nj)! (The training and decoding process has file-granularity)"
  exit 1;
  train_nj=$nj_max
fi
train_data_dir=`readlink -f ./data/raw_train_data`
my_data_dir=$train_data_dir

if [ ! -f ${datadir}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Preparing ${type} stm files in ${datadir} on" `date`
  echo ---------------------------------------------------------------------
  
  local/prepare_stm.pl --fragmentMarkers \-\*\~ ${datadir}

  if [ ! -f ${datadir}/.plp.done ]; then
    echo ---------------------------------------------------------------------
    echo "Preparing ${type} parametrization files in ${datadir} on" `date`
    echo ---------------------------------------------------------------------
    make_plp ${dirid}
    touch ${datadir}/.plp.done
  fi

  touch ${datadir}/.done
fi

#####################################################################
#
# data directory preparation
#
#####################################################################
echo ---------------------------------------------------------------------
echo "Preparing ${type} kws data files in ${datadir} on" `date`
echo ---------------------------------------------------------------------
if ! $skip_kws  && [ ! -f ${datadir}/kws/.done ] ; then
  if [[ $type == shadow ]]; then
    
    # we expect that the ${dev2shadow} as well as ${eval2shadow} already exist
    if [ ! -f data/${dev2shadow}/kws/.done ]; then
      echo "Error: data/${dev2shadow}/kws/.done does not exist."
      echo "Create the directory data/${dev2shadow} first, by calling $0 --type $dev2shadow --dataonly"
      exit 1
    fi
    if [ ! -f data/${eval2shadow}/kws/.done ]; then
      echo "Error: data/${eval2shadow}/kws/.done does not exist."
      echo "Create the directory data/${eval2shadow} first, by calling $0 --type $eval2shadow --dataonly"
      exit 1
    fi


    local/kws_data_prep.sh --case_insensitive $case_insensitive \
      "${icu_opt[@]}" \
      data/lang ${datadir} ${datadir}/kws
    utils/fix_data_dir.sh ${datadir}

    touch ${datadir}/kws/.done
  else
    kws_flags=()
    if [ ! -z $my_rttm_file ] ; then
      kws_flags+=(--rttm-file $my_rttm_file )
    fi
    if [ $my_subset_ecf ] ; then
      kws_flags+=(--subset-ecf $my_data_list)
    fi
    
    local/kws_setup.sh --case_insensitive $case_insensitive \
      "${kws_flags[@]}" "${icu_opt[@]}" \
      $my_ecf_file $my_kwlist_file data/lang ${datadir}

    touch ${datadir}/kws/.done
  fi
fi

if [[ ! -f data/train_whole/wav.scp || data/train_whole/wav.scp -ot "$train_data_dir" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing acoustic training lists in data/train on" `date`
  echo ---------------------------------------------------------------------
  mkdir -p data/train_whole
  local/prepare_acoustic_training_data_whole_separate_fillers.pl \
    --vocab data/local/lexicon.txt --fragmentMarkers \-\*\~ \
    $train_data_dir data/train_whole > data/train_whole/skipped_utts.log
  mv data/train_whole/text data/train_whole/text_orig
  if $keep_silence_segments; then
    cat data/train_whole/text_orig | awk '{if (NF == 2 && $2 == "<silence>") {print $1} else {print $0}}' > data/train_whole/text
  else
    num_silence_segments=$(cat data/train_whole/text_orig | awk '{if (NF == 2 && $2 == "<silence>") {print $0}}' | wc -l)
    num_keep_silence_segments=`echo $num_silence_segments | python -c "import sys; sys.stdout.write(\"%d\" % (float(sys.stdin.readline().strip()) * "$silence_segment_fraction"))"` 
    cat data/train_whole/text_orig \
      | awk 'BEGIN{i=0} \
      { \
        if (NF == 2 && $2 == "<silence>") { \
          if (i<'$num_keep_silence_segments') { \
            print $1; \
            i++; \
          } \
        } else {print $0}\
      }' > data/train_whole/text
  fi
  utils/fix_data_dir.sh data/train_whole
fi

if [[ ! -f data/train_whole/glm || data/train_whole/glm -ot "$glmFile" ]]; then
  echo ---------------------------------------------------------------------
  echo "Preparing train stm files in data/train_whole on" `date`
  echo ---------------------------------------------------------------------
  local/prepare_stm.pl --fragmentMarkers \-\*\~ data/train_whole || exit 1
fi

echo ---------------------------------------------------------------------
echo "Starting plp feature extraction for data/train_whole in plp_whole on" `date`
echo ---------------------------------------------------------------------

use_pitch=false
use_ffv=false

if [ ! -f data/train_whole/.plp.done ]; then
  steps/make_plp.sh --cmd "$train_cmd" --nj $train_nj data/train_whole exp/make_plp/train_whole plp_whole

  steps/compute_cmvn_stats.sh \
    data/train_whole exp/make_plp/train_whole plp_whole
  # In case plp or pitch extraction failed on some utterances, delist them
  utils/fix_data_dir.sh data/train_whole
  touch data/train_whole/.plp.done
fi

if [ ! -f data/train_whole_sub3/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Subsetting monophone training data in data/train_whole_sub[123] on" `date`
  echo ---------------------------------------------------------------------
  numutt=`cat data/train_whole/feats.scp | wc -l`;
  utils/subset_data_dir.sh data/train_whole  5000 data/train_whole_sub1
  if [ $numutt -gt 10000 ] ; then
    utils/subset_data_dir.sh data/train_whole 10000 data/train_whole_sub2
  else
    (cd data; ln -s train_whole train_whole_sub2 )
  fi
  if [ $numutt -gt 20000 ] ; then
    utils/subset_data_dir.sh data/train_whole 20000 data/train_whole_sub3
  else
    (cd data; ln -s train_whole train_whole_sub3 )
  fi

  touch data/train_whole_sub3/.done
fi

echo ---------------------------------------------------------------------
echo "Resegment data in data_reseg on " `date`
echo ---------------------------------------------------------------------

sh -x local/run_resegment.sh --remove-oov $remove_oov --train-nj $train_nj --nj $my_nj --type $type --segmentation_opts "$segmentation_opts" || exit 1

datadir=data_reseg/${type}
#####################################################################
#
# data directory preparation
#
#####################################################################
echo ---------------------------------------------------------------------
echo "Preparing ${type} kws data files in ${datadir} on" `date`
echo ---------------------------------------------------------------------
if ! $skip_kws  && [ ! -f ${datadir}/kws/.done ] ; then
  if [[ $type == shadow ]]; then
    
    # we expect that the ${dev2shadow} as well as ${eval2shadow} already exist
    if [ ! -f data/${dev2shadow}/kws/.done ]; then
      echo "Error: data/${dev2shadow}/kws/.done does not exist."
      echo "Create the directory data/${dev2shadow} first, by calling $0 --type $dev2shadow --dataonly"
      exit 1
    fi
    if [ ! -f data/${eval2shadow}/kws/.done ]; then
      echo "Error: data/${eval2shadow}/kws/.done does not exist."
      echo "Create the directory data/${eval2shadow} first, by calling $0 --type $eval2shadow --dataonly"
      exit 1
    fi


    local/kws_data_prep.sh --case_insensitive $case_insensitive \
      "${icu_opt[@]}" \
      data/lang ${datadir} ${datadir}/kws
    utils/fix_data_dir.sh ${datadir}

    touch ${datadir}/kws/.done
  else
    kws_flags=()
    if [ ! -z $my_rttm_file ] ; then
      kws_flags+=(--rttm-file $my_rttm_file )
    fi
    if [ $my_subset_ecf ] ; then
      kws_flags+=(--subset-ecf $my_data_list)
    fi
    
    local/kws_setup.sh --case_insensitive $case_insensitive \
      "${kws_flags[@]}" "${icu_opt[@]}" \
      $my_ecf_file $my_kwlist_file data/lang ${datadir}

    touch ${datadir}/kws/.done
  fi
fi


if $data_only ; then
  echo "Exiting, as data-only was requested..."
  exit 0;
fi


####################################################################
##
## FMLLR decoding 
##
####################################################################
tri5=tri5
decode=exp/${tri5}/decode_${dirid}_reseg

if [ ! -f ${decode}/.done ]; then
  echo ---------------------------------------------------------------------
  echo "Spawning decoding with SAT models  on" `date`
  echo ---------------------------------------------------------------------
  utils/mkgraph.sh \
    data/lang exp/$tri5 exp/$tri5/graph |tee exp/$tri5/mkgraph.log

  mkdir -p $decode
  #By default, we do not care about the lattices for this step -- we just want the transforms
  #Therefore, we will reduce the beam sizes, to reduce the decoding times
  steps/decode_fmllr_extra.sh --skip-scoring false \
    --nj $my_nj --cmd "$decode_cmd" "${decode_extra_opts[@]}"\
    exp/$tri5/graph ${datadir} ${decode} |tee ${decode}/decode.log
  
  local/run_kws_stt_task.sh --cer $cer --max-states $max_states \
    --cmd "$decode_cmd" --skip-kws $skip_kws --skip-stt $skip_stt --wip $wip \
    "${shadow_set_extra_opts[@]}" "${lmwt_plp_extra_opts[@]}" \
    ${datadir} data/lang $decode
  
  touch ${decode}/.done
fi

exit 0
