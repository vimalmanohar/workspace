#!/usr/bin/python2

################################################################################
#
# This script was written to extract the portions of false speech
# and false silences using automatic segmentation tools
# It assumes input in the form of two Kaldi segments files, i.e. a file each of
# whose lines contain four space-separated values:
#
#    UtteranceID  FileID  StartTime EndTime
#
################################################################################

import sys

def main():

  if len(sys.argv) != 3:
    sys.stderr.write("Usage: " + sys.argv[0] + " reference_segments proposed_segments\n")
    sys.exit(1)
  else:
    sys.stderr.write(str(sys.argv) + "\n")
    reference_segmentation_file = sys.argv[1]
    proposed_segmentation_file = sys.argv[2]

  frame_shift = 100

################################################################################
# First read the reference segmentation, and
# store the start- and end-times of all segments in each file.
################################################################################

  ref_file_handle = open(reference_segmentation_file, 'r')
  ref_start_segments = {}
  ref_end_segments = {}
  ref_durations = {}
  ref_segments = {}
  ref_max_time = {}

  for line in ref_file_handle.readlines():
    splits = line.strip().split()
    if len(splits) != 4:
      sys.stderr.write("Skipping unparsable line in file " + reference_segmentation_file + "\n" + line)
      continue
    fileID = splits[1]
    start_time = float(splits[2])
    end_time = float(splits[3])
    ref_start_segments.setdefault(fileID, [])
    ref_start_segments[fileID].append(start_time)
    ref_end_segments.setdefault(fileID, [])
    ref_end_segments[fileID].append(end_time)
    ref_durations.setdefault(fileID, [])
    ref_durations[fileID].append(end_time - start_time)
    ref_max_time[fileID] = int(max(ref_max_time.setdefault(fileID,0.0), end_time * frame_shift))

  for fileID in ref_start_segments:
    i = 0
    start_ptr = 0       # Start
    end_ptr = 0         # End
    frame_class = 0
    ref_start_segments[fileID].sort()
    ref_end_segments[fileID].sort()
    ref_segments.setdefault(fileID, [])

    while i < ref_max_time[fileID]:
      if start_ptr < len(ref_start_segments[fileID]) and i == int(ref_start_segments[fileID][start_ptr] * frame_shift):
        frame_class = 1
        ref_segments[fileID].append(frame_class)
        i += 1
        start_ptr += 1
      if end_ptr < len(ref_end_segments[fileID]) and i == int(ref_end_segments[fileID][end_ptr] * frame_shift):
        ref_segments[fileID].append(frame_class)
        frame_class = 0
        end_ptr += 1
        i += 1
      if i < ref_max_time[fileID]:
        ref_segments[fileID].append(frame_class)
        i += 1

################################################################################
# Process hypothesized segments sequentially, and gather speech/nonspeech stats
################################################################################

  hyp_file_handle = open(proposed_segmentation_file, 'r')
  hyp_start_segments = {}
  hyp_end_segments = {}
  hyp_durations = {}
  hyp_segments = {}
  hyp_max_time = {}

  for line in hyp_file_handle.readlines():
    splits = line.strip().split()
    if len(splits) != 4:
      sys.stderr.write("Skipping unparsable line in file " + proposed_segmentation_file + "\n" + line)
      continue
    fileID = splits[1]
    start_time = float(splits[2])
    end_time = float(splits[3])
    hyp_start_segments.setdefault(fileID, [])
    hyp_start_segments[fileID].append(start_time)
    hyp_end_segments.setdefault(fileID, [])
    hyp_end_segments[fileID].append(end_time)
    hyp_durations.setdefault(fileID, [])
    hyp_durations[fileID].append(end_time - start_time)
    hyp_max_time[fileID] = int(max(hyp_max_time.setdefault(fileID,0.0), end_time * frame_shift))

  for fileID in hyp_start_segments:
    if fileID not in ref_segments:
      sys.stderr.write(fileID + " not present in " + reference_segmentation_file + '\n')
      sys.exit(1)
    i = 0
    start_ptr = 0       # Start
    end_ptr = 0         # End
    frame_class = 0
    hyp_start_segments[fileID].sort()
    hyp_end_segments[fileID].sort()
    hyp_segments.setdefault(fileID, [])

    while i < hyp_max_time[fileID]:
      if start_ptr < len(hyp_start_segments[fileID]) and i == int(hyp_start_segments[fileID][start_ptr] * frame_shift):
        frame_class = 1
        hyp_segments[fileID].append(frame_class)
        i += 1
        start_ptr += 1
      if end_ptr < len(hyp_end_segments[fileID]) and  i == int(hyp_end_segments[fileID][end_ptr] * frame_shift):
        hyp_segments[fileID].append(frame_class)
        frame_class = 0
        end_ptr += 1
        i += 1
      if i < hyp_max_time[fileID]:
        hyp_segments[fileID].append(frame_class)
        i += 1
    max_time = max(hyp_max_time[fileID], ref_max_time[fileID])

    for i in range(hyp_max_time[fileID], max_time):
      hyp_segments[fileID].append(0)
    for i in range(ref_max_time[fileID], max_time):
      ref_segments[fileID].append(0)

    true_pos = []
    true_neg = []
    false_pos = []
    false_neg = []

    for i in range(0, max_time):
      if hyp_segments[fileID][i] == 1 and ref_segments[fileID][i] == 1:
        true_pos.append(1)
      else:
        true_pos.append(0)
      if hyp_segments[fileID][i] == 1 and ref_segments[fileID][i] == 0:
        false_pos.append(1)
      else:
        false_pos.append(0)
      if hyp_segments[fileID][i] == 0 and ref_segments[fileID][i] == 0:
        true_neg.append(1)
      else:
        true_neg.append(0)
      if hyp_segments[fileID][i] == 0 and ref_segments[fileID][i] == 1:
        false_neg.append(1)
      else:
        false_neg.append(0)

    true_pos_start_time = []
    true_neg_start_time = []
    false_neg_start_time = []
    false_pos_start_time = []
    true_pos_end_time = []
    true_neg_end_time = []
    false_neg_end_time = []
    false_pos_end_time = []

    if true_pos[0] == 1:
      true_pos_start_time.append(0)
    if false_pos[0] == 1:
      false_pos_start_time.append(0)
    if true_neg[0] == 1:
      true_neg_start_time.append(0)
    if false_neg[0] == 1:
      false_neg_start_time.append(0)

    for i in range(0, max_time-1):
      if true_pos[i] == 0 and true_pos[i+1] == 1:
        true_pos_start_time.append(i+1)
      if false_pos[i] == 0 and false_pos[i+1] == 1:
        false_pos_start_time.append(i+1)
      if false_neg[i] == 0 and false_neg[i+1] == 1:
        false_neg_start_time.append(i+1)
      if true_neg[i] == 0 and true_neg[i+1] == 1:
        true_neg_start_time.append(i+1)
      if true_pos[i] == 1 and true_pos[i+1] == 0:
        true_pos_end_time.append(i)
        if len(true_pos_start_time) == 0:
          continue
        sys.stdout.write(fileID+"-%06d-%06d-true-pos" % (true_pos_start_time[0], true_pos_end_time[0]) + '\t' + fileID + '\t' + str(true_pos_start_time[0]/float(frame_shift)) + '\t' + str(true_pos_end_time[0]/float(frame_shift)) + '\n')
        true_pos_start_time.pop(0)
        true_pos_end_time.pop(0)
      if false_pos[i] == 1 and false_pos[i+1] == 0:
        false_pos_end_time.append(i)
        if len(false_pos_start_time) == 0:
          continue
        sys.stdout.write(fileID+"-%06d-%06d-false-pos" % (false_pos_start_time[0], false_pos_end_time[0]) + '\t' + fileID + '\t' + str(false_pos_start_time[0]/float(frame_shift)) + '\t' + str(false_pos_end_time[0]/float(frame_shift)) + '\n')
        false_pos_start_time.pop(0)
        false_pos_end_time.pop(0)
      if false_neg[i] == 1 and false_neg[i+1] == 0:
        false_neg_end_time.append(i)
        if len(false_neg_start_time) == 0:
          continue
        sys.stdout.write(fileID+"-%06d-%06d-false-neg" % (false_neg_start_time[0], false_neg_end_time[0]) + '\t' + fileID + '\t' + str(false_neg_start_time[0]/float(frame_shift)) + '\t' + str(false_neg_end_time[0]/float(frame_shift)) + '\n')
        false_neg_start_time.pop(0)
        false_neg_end_time.pop(0)
      if true_neg[i] == 1 and true_neg[i+1] == 0:
        true_neg_end_time.append(i)
        if len(true_neg_start_time) == 0:
          continue
        sys.stdout.write(fileID+"-%06d-%06d-true-neg" % (true_neg_start_time[0], true_neg_end_time[0]) + '\t' + fileID + '\t' + str(true_neg_start_time[0]/float(frame_shift)) + '\t' + str(true_neg_end_time[0]/float(frame_shift)) + '\n')
        true_neg_start_time.pop(0)
        true_neg_end_time.pop(0)

if __name__ == '__main__':
  main()
