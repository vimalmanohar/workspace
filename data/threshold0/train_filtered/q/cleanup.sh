#!/bin/bash
cd /export/a14/vmanoha1/workspace/babel_assamese
. ./path.sh
( echo '#' Running on `hostname`
  echo '#' Started at `date`
  echo -n '# '; cat <<EOF
gunzip -c exp/sgmm5_denlats/lat.$SGE_TASK_ID.gz | lattice-oracle ark:- "ark:utils/sym2int.pl -f 2- data/lang/words.txt data/train/text|" ark,t:- 3>&1 1>&2 2>&3 | awk 'BEGIN {id=""} /Lattice/ {id=$2} /best cost/ {if ( $NF == 0 ) print id}' | awk -F_ '{print $0" "$1"_"$2}' > data/train_filtered/utt2spk_split$SGE_TASK_ID 
EOF
) >data/train_filtered/log/cleanup.$SGE_TASK_ID.log
time1=`date +"%s"`
 ( gunzip -c exp/sgmm5_denlats/lat.$SGE_TASK_ID.gz | lattice-oracle ark:- "ark:utils/sym2int.pl -f 2- data/lang/words.txt data/train/text|" ark,t:- 3>&1 1>&2 2>&3 | awk 'BEGIN {id=""} /Lattice/ {id=$2} /best cost/ {if ( $NF == 0 ) print id}' | awk -F_ '{print $0" "$1"_"$2}' > data/train_filtered/utt2spk_split$SGE_TASK_ID  ) 2>>data/train_filtered/log/cleanup.$SGE_TASK_ID.log >>data/train_filtered/log/cleanup.$SGE_TASK_ID.log
time2=`date +"%s"`
ret=$?
echo '#' Accounting: time=$(($time2-$time1)) threads=1 >>data/train_filtered/log/cleanup.$SGE_TASK_ID.log
echo '#' Finished at `date` with status $ret >>data/train_filtered/log/cleanup.$SGE_TASK_ID.log
[ $ret -eq 137 ] && exit 100;
touch data/train_filtered/q/done.69426.$SGE_TASK_ID
exit $[$ret ? 1 : 0]
## submitted with:
# qsub -S /bin/bash -v PATH -cwd -j y -o data/train_filtered/q/cleanup.log -l arch=*64,mem_free=2G,ram_free=2G  -t 1:16 /export/a14/vmanoha1/workspace/babel_assamese/data/train_filtered/q/cleanup.sh >>data/train_filtered/q/cleanup.log 2>&1
