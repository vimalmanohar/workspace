name=min.2s.silenceproportion.30pc.noremovenoise
silence_proportion=0.30
min_inter_utt_silence_length=2.0
remove_noise_only_segments=false
local/segmentation_joint_with_analysis.py --remove-noise-only-segments $remove_noise_only_segments --reference-rttm mitfa.rttm --max-length-diff 0.4 --verbose 2 --min-inter-utt-silence-length $min_inter_utt_silence_length --silence-proportion $silence_proportion  exp/tri4b_whole_resegment_dev10h/classes 2> exp/tri4b_whole_resegment_dev10h/segment.$name.log | sort > exp/tri4b_whole_resegment_dev10h/joint_segments.$name
./evaluate_segmentation.pl exp/tri4b_whole_resegment_dev10h/rttm_segments exp/tri4b_whole_resegment_dev10h/joint_segments.$name &> exp/tri4b_whole_resegment_dev10h/segmentation.diff.$name
