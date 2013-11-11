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
      for j in range(0, self.N):
        if self.true_count[i] > 0:
          file_handle.write("%6s classified as %6s: %4d (%2.3f)\n" % (self.inverse_phone_map[i], self.inverse_phone_map[j],  self.confusion_matrix[i][j], float(self.confusion_matrix[i][j]*100)/ self.true_count[i]))

    #if self.write_length_stats:
    #  for i in range(0,self.N):
    #    self.max_length[i]    = max([0]+self.state_count[i])
    #    self.min_length[i]    = min([10000]+self.state_count[i])
    #    self.mean_length[i]   = mean(self.state_count[i])
    #    try:
    #      self.percentile25[i]  = np.percentile(self.state_count[i], 25)
    #    except ValueError:
    #      self.percentile25[i] = 0
    #    try:
    #      self.percentile50[i]  = np.percentile(self.state_count[i], 50)
    #    except ValueError:
    #      self.percentile50[i] = 0
    #    try:
    #      self.percentile75[i]  = np.percentile(self.state_count[i], 75)
    #    except ValueError:
    #      self.percentile75[i] = 0

    #  file_handle.write("Lengths of different segments:\n")
    #  file_handle.write("%40s:\n %s\n" % ("Silence classified as Silence",  str(self.state_count[0]) ))
    #  file_handle.write("%40s:\n %s\n" % ("Silence classified as Noise",    str(self.state_count[1]) ))
    #  file_handle.write("%40s:\n %s\n" % ("Silence classified as Speech",   str(self.state_count[2]) ))
    #  file_handle.write("%40s:\n %s\n" % ("Noise classified as Silence",    str(self.state_count[3]) ))
    #  file_handle.write("%40s:\n %s\n" % ("Noise classified as Noise",      str(self.state_count[4]) ))
    #  file_handle.write("%40s:\n %s\n" % ("Noise classified as Speech",     str(self.state_count[5]) ))
    #  file_handle.write("%40s:\n %s\n" % ("Speech classified as Silence",   str(self.state_count[6]) ))
    #  file_handle.write("%40s:\n %s\n" % ("Speech classified as Noise",     str(self.state_count[7]) ))
    #  file_handle.write("%40s:\n %s\n" % ("Speech classified as Speech",    str(self.state_count[8]) ))

    #  file_handle.write("%40s: Min: %4d Max: %4d Mean: %4d percentile25: %4d percentile50: %4d percentile75: %4d\n" % ("Silence classified as Silence",  self.min_length[0], self.max_length[0], self.mean_length[0], self.percentile25[0], self.percentile50[0], self.percentile75[0]))
    #  file_handle.write("%40s: Min: %4d Max: %4d Mean: %4d percentile25: %4d percentile50: %4d percentile75: %4d\n" % ("Silence classified as Noise",    self.min_length[1], self.max_length[1], self.mean_length[1], self.percentile25[1], self.percentile50[1], self.percentile75[1]))
    #  file_handle.write("%40s: Min: %4d Max: %4d Mean: %4d percentile25: %4d percentile50: %4d percentile75: %4d\n" % ("Silence classified as Speech",   self.min_length[2], self.max_length[2], self.mean_length[2], self.percentile25[2], self.percentile50[2], self.percentile75[2]))
    #  file_handle.write("%40s: Min: %4d Max: %4d Mean: %4d percentile25: %4d percentile50: %4d percentile75: %4d\n" % ("Noise classified as Silence",    self.min_length[3], self.max_length[3], self.mean_length[3], self.percentile25[3], self.percentile50[3], self.percentile75[3]))
    #  file_handle.write("%40s: Min: %4d Max: %4d Mean: %4d percentile25: %4d percentile50: %4d percentile75: %4d\n" % ("Noise classified as Noise",      self.min_length[4], self.max_length[4], self.mean_length[4], self.percentile25[4], self.percentile50[4], self.percentile75[4]))
    #  file_handle.write("%40s: Min: %4d Max: %4d Mean: %4d percentile25: %4d percentile50: %4d percentile75: %4d\n" % ("Noise classified as Speech",     self.min_length[5], self.max_length[5], self.mean_length[5], self.percentile25[5], self.percentile50[5], self.percentile75[5]))
    #  file_handle.write("%40s: Min: %4d Max: %4d Mean: %4d percentile25: %4d percentile50: %4d percentile75: %4d\n" % ("Speech classified as Silence",   self.min_length[6], self.max_length[6], self.mean_length[6], self.percentile25[6], self.percentile50[6], self.percentile75[6]))
    #  file_handle.write("%40s: Min: %4d Max: %4d Mean: %4d percentile25: %4d percentile50: %4d percentile75: %4d\n" % ("Speech classified as Noise",     self.min_length[7], self.max_length[7], self.mean_length[7], self.percentile25[7], self.percentile50[7], self.percentile75[7]))
    #  file_handle.write("%40s: Min: %4d Max: %4d Mean: %4d percentile25: %4d percentile50: %4d percentile75: %4d\n" % ("Speech classified as Speech",    self.min_length[8], self.max_length[8], self.mean_length[8], self.percentile25[8], self.percentile50[8], self.percentile75[8]))

    #if self.write_markers:
    #  file_handle.write("Start frames of different segments:\n")
    #  file_handle.write("%40s:\n %s\n" % ("Silence classified as Silence",  str([str(self.markers[0][i])+' ('+ str(self.state_count[0][i])+')' for i in range(0, len(self.state_count[0]))])))
    #  file_handle.write("%40s:\n %s\n" % ("Silence classified as Noise",    str([str(self.markers[1][i])+' ('+ str(self.state_count[1][i])+')' for i in range(0, len(self.state_count[1]))])))
    #  file_handle.write("%40s:\n %s\n" % ("Silence classified as Speech",   str([str(self.markers[2][i])+' ('+ str(self.state_count[2][i])+')' for i in range(0, len(self.state_count[2]))])))
    #  file_handle.write("%40s:\n %s\n" % ("Noise classified as Silence",    str([str(self.markers[3][i])+' ('+ str(self.state_count[3][i])+')' for i in range(0, len(self.state_count[3]))])))
    #  file_handle.write("%40s:\n %s\n" % ("Noise classified as Noise",      str([str(self.markers[4][i])+' ('+ str(self.state_count[4][i])+')' for i in range(0, len(self.state_count[4]))])))
    #  file_handle.write("%40s:\n %s\n" % ("Noise classified as Speech",     str([str(self.markers[5][i])+' ('+ str(self.state_count[5][i])+')' for i in range(0, len(self.state_count[5]))])))
    #  file_handle.write("%40s:\n %s\n" % ("Speech classified as Silence",   str([str(self.markers[6][i])+' ('+ str(self.state_count[6][i])+')' for i in range(0, len(self.state_count[6]))])))
    #  file_handle.write("%40s:\n %s\n" % ("Speech classified as Noise",     str([str(self.markers[7][i])+' ('+ str(self.state_count[7][i])+')' for i in range(0, len(self.state_count[7]))])))
    #  file_handle.write("%40s:\n %s\n" % ("Speech classified as Speech",    str([str(self.markers[8][i])+' ('+ str(self.state_count[8][i])+')' for i in range(0, len(self.state_count[8]))])))

def main():
  parser = ArgumentParser(description='Analyse alignment using force alignment data')
  parser.add_argument('-l','--print-length-stats', dest='write_length_stats', action='store_true', help='Print length of the difference classes')
  parser.add_argument('-m','--print-start-markers', dest='write_markers', action='store_true', help='Print start markers of the difference classes')
  parser.add_argument('-p', '--phones', dest='phone_map_file', default='data/lang/phones.txt', help='Phone map file')
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
          this_frame_diff.state_count[ref][pred].append(count)
          this_frame_diff.markers[ref][pred].append(i-count)
          frame_diff.state_count[ref][pred].append(count)
          frame_diff.markers[ref][pred].append(i-count)
        count = 1
        prev_state = state
      else:
        count += 1

    sys.stdout.write("\n"+file_id+"\n")
    this_frame_diff.write()

  sys.stdout.write("\nTOTAL\n")
  frame_diff.write()

if __name__ == '__main__':
  main()

