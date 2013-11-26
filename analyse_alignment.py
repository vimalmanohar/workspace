#!/usr/bin/python

import argparse, sys, os, glob
import numpy as np
from argparse import ArgumentParser

frame_shift = 0.01

def mean(x):
  try:
    return float(sum(x))/len(x)
  except Exception:
    return 0

class Analysis:
  def __init__(self, phone_map, options = None):
    self.phone_map = phone_map
    self.N = len(phone_map)
    self.inverse_phone_map = [ -1 for i in range(0, self.N) ]
    for i, val in phone_map.items():
      self.inverse_phone_map[val] = i
    self.confusion_matrix = [[] for i in range(0, self.N)]
    self.state_count = [[] for i in range(0, self.N)]
    self.markers = [[] for i in range(0, self.N)]
    for i in range(0, self.N):
      self.confusion_matrix[i] = [[] for j in range(0, self.N)]
      self.state_count[i] = [[] for j in range(0, self.N)]
      self.markers[i] = [[] for j in range(0, self.N)]
      for j in range(0, self.N):
        self.confusion_matrix[i][j] = 0
        self.state_count[i][j] = []
        self.markers[i][j] = []
    self.true_count = [ 0 for i in range(0, self.N) ]
    self.write_length_stats = options.write_length_stats
    self.write_markers = options.write_markers

  def write(self, file_handle = sys.stdout):
    for i in range(0, self.N):
      self.true_count[i] = sum(self.confusion_matrix[i])
      if self.true_count[i] == 0:
        continue
      for j in range(0, self.N):
        if self.confusion_matrix[i][j] == 0:
          continue
        file_handle.write("%6s classified as %6s: %4d (%2.3f)\n" % (self.inverse_phone_map[i], self.inverse_phone_map[j],  self.confusion_matrix[i][j], float(self.confusion_matrix[i][j]*100)/ self.true_count[i]))

    if self.write_length_stats:
      file_handle.write("Lengths of different segments:\n")
      for i in range(0, self.N):
        if self.true_count[i] == 0:
          continue
        for j in range(0, self.N):
          if len(self.state_count[i][j]) == 0:
            continue
          self.max_length    = max([0]+self.state_count[i][j])
          self.min_length    = min([10000]+self.state_count[i][j])
          self.mean_length   = mean(self.state_count[i][j])
          try:
            self.percentile25  = np.percentile(self.state_count[i][j], 25)
          except ValueError:
            self.percentile25 = 0
          try:
            self.percentile50  = np.percentile(self.state_count[i][j], 50)
          except ValueError:
            self.percentile50 = 0
          try:
            self.percentile75  = np.percentile(self.state_count[i][j], 75)
          except ValueError:
            self.percentile75 = 0

          file_handle.write("%6s classified as %6s: \n%s\n" % (self.inverse_phone_map[i], self.inverse_phone_map[j], str(self.state_count[i][j]) ))
          file_handle.write("%6s classified as %6s: Min: %4d Max: %4d Mean: %4d percentile25: %4d percentile50: %4d percentile75: %4d\n" % (self.inverse_phone_map[i], self.inverse_phone_map[j], self.min_length, self.max_length, self.mean_length, self.percentile25, self.percentile50, self.percentile75))

    if self.write_markers:
      file_handle.write("Start frames of different segments:\n")
      for i in range(0, self.N):
        for j in range(0, self.N):
          if len(self.state_count[i][j]) == 0:
            continue
          file_handle.write("%6s classified as %6s: \n%s\n" % (self.inverse_phone_map[i], self.inverse_phone_map[j], str([str(self.markers[i][j][k])+' ('+ str(self.state_count[i][j][k])+')' for k in range(0, len(self.state_count[i][j]))])))

def main():
  parser = ArgumentParser(description='Analyse alignment using force alignment data')
  parser.add_argument('-l','--print-length-stats', dest='write_length_stats', action='store_true', help='Print length of the difference classes')
  parser.add_argument('-m','--print-start-markers', dest='write_markers', action='store_true', help='Print start markers of the difference classes')
  parser.add_argument('-p', '--phones', dest='phone_map_file', default='data/lang/phones.txt', help='Phone map file')
  parser.add_argument('-r', '--results-dir', dest='results_dir', help='Results dir')
  parser.add_argument('args', nargs=2, help='<reference_dir> <prediction_dir>')
  options = parser.parse_args()

  reference_dir = options.args[0]
  prediction_dir = options.args[1]

  phone_map_file = options.phone_map_file

  reference = dict([ (f.split('/')[-1][0:-4], []) for f in glob.glob(reference_dir + "/*.ref") ])
  prediction = dict([ (f.split('/')[-1][0:-5], []) for f in glob.glob(prediction_dir + "/*.pred") ])

  phone_map = {}
  for line in open(phone_map_file).readlines():
    splits = line.strip().split()
    phone_map[splits[0]] = int(splits[1])

  frame_diff = Analysis(phone_map, options)
  frame_diff.write_markers = False

  for file_id in prediction:
    try:
      this_pred = open(prediction_dir+"/"+file_id+".pred").readline().strip().split()[1:]
    except IOError:
      sys.stderr.write("Unable to open " + prediction_dir+"/"+file_id+".pred\tSkipping utterance\n")
      continue

    if file_id not in reference:
      sys.stderr.write(reference_dir+"/"+file_id+".ref not found\tSkipping utterance\n")
      continue

    try:
      this_ref = open(reference_dir+"/"+file_id+".ref").readline().strip().split()[1:]
    except IOError:
      sys.stderr.write("Unable to open " + reference_dir+"/"+file_id+".ref\tSkipping utterance\n")
      continue

    this_frame_diff = Analysis(phone_map, options)

    this_len = len(this_pred)
    if len(this_ref) > this_len:
      this_pred.extend(["SIL"]*(len(this_ref) - this_len))
      this_len = len(this_ref)
    elif len(this_ref) < this_len:
      this_ref.extend(["SIL"]*(this_len - len(this_ref)))
      this_len = len(this_ref)

    count = 0
    prev_state = None
    for i in range(0, this_len):
      ref = phone_map[this_ref[i]]
      pred = phone_map[this_pred[i]]
      state = (ref, pred)
      frame_diff.confusion_matrix[ref][pred] += 1
      this_frame_diff.confusion_matrix[ref][pred] += 1
      if prev_state != state:
        if count > 0:
          ref, pred = prev_state
          this_frame_diff.state_count[ref][pred].append(count)
          this_frame_diff.markers[ref][pred].append(i-count)
          frame_diff.state_count[ref][pred].append(count)
          frame_diff.markers[ref][pred].append(i-count)
        count = 1
        prev_state = state
      else:
        count += 1

    if options.results_dir is None:
      out_file = sys.stdout
    else:
      out_file = open(options.results_dir+"/"+file_id+".align_results", 'w')
    out_file.write("\n"+file_id+"\n")
    this_frame_diff.write(out_file)
    out_file.close()

  if options.results_dir is None:
    out_file = sys.stdout
  else:
    out_file = open(options.results_dir+"/TOTAL"+".align_results", 'w')
  out_file.write("\nTOTAL\n")
  frame_diff.write(out_file)

if __name__ == '__main__':
  main()

