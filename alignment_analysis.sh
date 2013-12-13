#!/bin/bash
set -e
set -o pipefail

[ -f ./cmd.sh ] && . ./cmd.sh

# begin configuration section.
cmd=$decode_cmd
cleanup=false
prefix="BABEL_BP_102"
segmentation_opts="--remove-noise-only-segments true --split-on-noise-transitions true" 
data=
data_reseg=
alidir=

#end configuration section.

[ -f ./path.sh ] && . ./path.sh
. parse_options.sh || exit 1;

if [ $# -ne 2 ]; then
  echo "Usage: $0 [options] <force-ali-dir> <phone-decode-dir>"
  echo " Options:"
  echo "    --cmd (run.pl|queue.pl...)      # specify how to run the sub-processes."
  echo "e.g.:"
  echo "$0 exp/sgmm5/align_fmllr_dev10h exp/tri4b_whole_resegment_dev10h"
  exit 1;
fi

force_alidir=$1
dir=$2

[ -d $force_alidir ] || exit 1
[ -d $dir ] || exit 1
[ -f $force_alidir/ali.1.gz ] || exit 1
[ -z $alidir ] && [ ! -f $dir/classes.1.gz ] && exit 1

force_ali_model=$force_alidir/../final.mdl
[ -e $force_ali_model ] || exit 1

nj=`cat $force_alidir/num_jobs` || exit 1
if [ ! -f $dir/ref_align.done ]; then
  $cmd JOB=1:$nj $dir/log/ref_align.JOB.log \
    ali-to-phones --per-frame=true $force_ali_model \
    "ark:gunzip -c $force_alidir/ali.JOB.gz|" ark,t:- \| \
    utils/int2sym.pl -f 2- data/lang/phones.txt \| \
    gzip -c '>' $dir/ref_align.JOB.gz || exit 1

  rm -rf $dir/ref_align
  mkdir -p $dir/ref_align
  for n in `seq $nj`; do gunzip -c $dir/ref_align.$n.gz; done \
    | sort | ./get_reference_classes.py --align --prefix $prefix - $dir/ref_align || exit 1
  touch $dir/ref_align.done
fi

if [ ! -f $dir/ref_classes.done ]; then
  $cmd JOB=1:$nj $dir/log/ref_classify.JOB.log \
    ali-to-phones --per-frame=true $force_ali_model \
    "ark:gunzip -c $force_alidir/ali.JOB.gz|" ark,t:- \| \
    utils/int2sym.pl -f 2- data/lang/phones.txt \| \
    utils/apply_map.pl -f 2- $dir/phone_map.txt \| \
    gzip -c '>' $dir/ref_classes.JOB.gz || exit 1
  [ -f $dir/ref_classes.1.gz ] || exit 1
  rm -rf $dir/ref_classes
  mkdir -p $dir/ref_classes

  for n in `seq $nj`; do gunzip -c $dir/ref_classes.$n.gz; done \
    | sort | ./get_reference_classes.py --prefix $prefix - $dir/ref_classes || exit 1
  cat $dir/ref_classes/*.ref | sort | utils/segmentation2.pl $segmentation_opts > $dir/ref_segments || exit 1

  $cleanup && rm $dir/ref_classes.*.gz
  touch $dir/ref_classes.done
fi

if [ ! -z $alidir ] && [ ! -f $dir/classes.1.gz ]; then
  nj=`cat $alidir/num_jobs` || exit 1;
  echo $nj > $dir/num_jobs

  model=$alidir/../final.mdl
  [ -f $model ] || exit 1
  
  $cmd JOB=1:$nj $dir/log/classify.JOB.log \
    ali-to-phones --per-frame=true "$model" "ark:gunzip -c $alidir/ali.JOB.gz|" ark,t:- \| \
    utils/int2sym.pl -f 2- data/lang/phones.txt \| \
    utils/apply_map.pl -f 2- $dir/phone_map.txt \| \
    gzip -c '>' $dir/classes.JOB.gz || exit 1
fi

if [ ! -z $alidir ] && [ ! -f $dir/pred.done ]; then
  nj=`cat $alidir/num_jobs` || exit 1;
  echo $nj > $dir/num_jobs

  model=$alidir/../final.mdl
  [ -f $model ] || exit 1
  
  $cmd JOB=1:$nj $dir/log/pred.JOB.log \
    ali-to-phones --per-frame=true "$model" "ark:gunzip -c $alidir/ali.JOB.gz|" ark,t:- \| \
    utils/int2sym.pl -f 2- data/lang/phones.txt \| \
    gzip -c '>' $dir/pred.JOB.gz || exit 1
  
  rm -rf $dir/pred
  mkdir -p $dir/pred
  nj=`cat $dir/num_jobs` || exit 1
  for n in `seq $nj`; do gunzip -c $dir/pred.$n.gz; done \
    | python -c "import sys 
for l in sys.stdin.readlines():
  line = l.strip()
  file_id = line.split()[0]
  out_handle = open(\""$dir"/pred/\"+file_id+\".pred\", 'w')
  out_handle.write(line)
  out_handle.close()"
  touch $dir/pred.done
fi

rm -rf $dir/classes
mkdir -p $dir/classes
nj=`cat $dir/num_jobs` || exit 1
if [ -z $(ls $dir/classes) ] || [ ! -f $dir/classes.done ]; then
  for n in `seq $nj`; do gunzip -c $dir/classes.$n.gz; done \
    | awk '{print "echo \""$0"\" > '$dir'/classes/"$1".pred"}' \
    | bash -e
  touch $dir/classes.done
fi

./analyse_segmentation.py -l -m $dir/ref_classes $dir/classes > $dir/segmentation_analysis.results

[ ! -z $data ] && ./evaluate_segmentation.pl $data/segments $dir/ref_segments &> $dir/ref_segmentation.diff
[ ! -z $data ] && [ ! -z $data_reseg ] && ./evaluate_segmentation.pl $data/segments $data_reseg/segments &> $dir/resegmentation.diff
[ ! -z $data ] && [ ! -z $data_reseg ] && ./evaluate_segmentation.pl $dir/ref_segments $data_reseg/segments &> $dir/ref_resegmentation.diff
