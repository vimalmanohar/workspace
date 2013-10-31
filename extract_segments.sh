decode_dir=$1
split_dir=$2
frame_shift=0.01

set -o pipefail
. ./path.sh

while read segment; do
  seg=($(echo $segment | python -c \
    "import sys
splits = sys.stdin.readline().strip().split()
if len(splits) == 0:
  sys.exit(0)
else:
  sys.stdout.write(\"%s %s %d %d\" % (splits[0],splits[1],int(float(splits[2])/"$frame_shift"),int(float(splits[3])/"$frame_shift")))" \
    | tr " " "\n"))

  utt_id=${seg[0]}
  #if [ "$(echo $utt_id | sed -n '/false/p' | wc -l)" -eq 0 ]; then
  #  continue
  #fi

  file_id=${seg[1]}
  start_time=${seg[2]}
  end_time=${seg[3]}

  for split in $(ls $split_dir); do
    if [ $(grep $file_id $split_dir/$split/utt2spk | wc -l) -gt 0 ]; then
      break
    fi
  done

  ali-to-phones --per-frame=true $decode_dir/../final.mdl "ark:gunzip -c $decode_dir/ali.$split.gz|" ark,t:- | grep $file_id | utils/int2sym.pl -f 2- data/lang/phones.txt | awk 'BEGIN{s='$start_time'; e='$end_time';printf("'$utt_id'\t")} {for (i=s; i<=e; i++) printf("%d(%s) ",i,$(i+2));} {printf "\n"}'  || exit 1
done
