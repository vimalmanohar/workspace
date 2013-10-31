#!/usr/bin/python

import argparse, sys, os
from argparse import ArgumentParser

frame_shift = 0.01

class Analysis:
  def __init__(self):
    self.sil_as_sil = 0
    self.sil_as_noise = 0
    self.sil_as_speech = 0
    self.noise_as_sil = 0
    self.noise_as_noise = 0
    self.noise_as_speech = 0
    self.speech_as_sil = 0
    self.speech_as_noise = 0
    self.speech_as_speech = 0

  def write(self, file_handle = sys.stdout):
    file_handle.write("%20s: %2.3f hrs\n" % ("True Silence", float(self.true_silence)*frame_shift/60/60))
    file_handle.write("%20s: %2.3f hrs\n" % ("True Noise", float(self.true_noise)*frame_shift/60/60))
    file_handle.write("%20s: %2.3f hrs\n" % ("True Speech", float(self.true_speech)*frame_shift/60/60))
    file_handle.write("%20s: %2.3f hrs\n" % ("Predicted Silence", float(self.predicted_silence)*frame_shift/60/60))
    file_handle.write("%20s: %2.3f hrs\n" % ("Predicted Noise", float(self.predicted_noise)*frame_shift/60/60))
    file_handle.write("%20s: %2.3f hrs\n" % ("Predicted Speech", float(self.predicted_speech)*frame_shift/60/60))
    file_handle.write("%40s: %10d (%2.3f)\n" % ("Silence classified as Silence",  self.sil_as_sil				, float(self.sil_as_sil			 *100)/ self.true_silence ))
    file_handle.write("%40s: %10d (%2.3f)\n" % ("Silence classified as Noise",    self.sil_as_noise			, float(self.sil_as_noise		 *100)/ self.true_silence ))
    file_handle.write("%40s: %10d (%2.3f)\n" % ("Silence classified as Speech",   self.sil_as_speech		, float(self.sil_as_speech	 *100)/ self.true_silence ))
    file_handle.write("%40s: %10d (%2.3f)\n" % ("Noise classified as Silence",    self.noise_as_sil			, float(self.noise_as_sil		 *100)/ self.true_noise ))
    file_handle.write("%40s: %10d (%2.3f)\n" % ("Noise classified as Noise",      self.noise_as_noise		, float(self.noise_as_noise	 *100)/ self.true_noise ))
    file_handle.write("%40s: %10d (%2.3f)\n" % ("Noise classified as Speech",     self.noise_as_speech	, float(self.noise_as_speech *100)/ self.true_noise ))
    file_handle.write("%40s: %10d (%2.3f)\n" % ("Speech classified as Silence",   self.speech_as_sil		, float(self.speech_as_sil	 *100)/self.true_speech))
    file_handle.write("%40s: %10d (%2.3f)\n" % ("Speech classified as Noise",     self.speech_as_noise	, float(self.speech_as_noise *100)/self.true_speech))
    file_handle.write("%40s: %10d (%2.3f)\n" % ("Speech classified as Speech",    self.speech_as_speech	, float(self.speech_as_speech*100)/self.true_speech))

  def compute_stats(self):
    self.true_silence   = self.sil_as_sil + self.sil_as_noise + self.sil_as_speech
    self.true_noise     = self.noise_as_sil + self.noise_as_noise + self.noise_as_speech
    self.true_speech    = self.speech_as_sil + self.speech_as_noise + self.speech_as_speech
    self.predicted_silence  = self.sil_as_sil + self.noise_as_sil + self.speech_as_sil
    self.predicted_noise    = self.sil_as_noise + self.noise_as_noise + self.speech_as_noise
    self.predicted_speech   = self.sil_as_speech + self.noise_as_speech + self.speech_as_speech

def main():
  parser = ArgumentParser(description='Analyse segmentation using RTTM file')
  parser.add_argument('args', nargs=3, help='<RTTM file> <Per frame class file> <temp_dir>')
  options = parser.parse_args()

  rttm_file = options.args[0]
  class_file = options.args[1]
  temp_dir = options.args[2]

  os.system("mkdir -p " + temp_dir)

  reference = {}
  read_rttm_file(open(rttm_file), reference, temp_dir)
  read_class_file(open(class_file), reference, temp_dir)

def read_rttm_file(rttm_file, reference, temp_dir):
  file_id = None
  this_file = []
  ref_file_handle = None
  for line in rttm_file.readlines():
    splits = line.strip().split()
    type1 = splits[0]
    if type1 == "SPEAKER":
      continue
    if splits[1] != file_id:
      # A different file_id. Need to open a different file to write
      if this_file != []:
        # If this_file is empty, no reference RTTM corresponding to the file_id
        # is read. This will happen at the start of the file_id. Otherwise it means a
        # contiguous segment of previous file_id is processed. So write it to the file.
        # corresponding to the previous file_id
        try:
          ref_file_handle.write(' '.join(this_file))
          # Close the previous file if any
          ref_file_handle.close()
          this_file = []
        except AttributeError:
          1==1

      file_id = splits[1]
      if (file_id not in reference):
        # First time seeing this file_id. Open a new file for writing.
        reference[file_id] = 1
        try:
          ref_file_handle = open(temp_dir+"/"+file_id+".ref", 'w')
        except IOError:
          sys.stderr.write("Unable to open " + temp_dir+"/"+file_id+".ref for writing\n")
          sys.exit(1)
        ref_file_handle.write(file_id + "\t")
      else:
        # This file has been seen before but not in the previous iteration.
        # The file has already been closed. So open it for append.
        try:
          this_file = open(temp_dir+"/"+file_id+".ref").readline().strip().split()[1:]
          ref_file_handle = open(temp_dir+"/"+file_id+".ref", 'a')
        except IOError:
          sys.stderr.write("Unable to open " + temp_dir+"/"+file_id+".ref for appending\n")
          sys.exit(1)

    i = len(this_file)
    category = splits[6]
    word = splits[5]
    start_time = int(float(splits[3])/frame_shift + 0.5)
    duration = int(float(splits[4])/frame_shift + 0.5)
    if i < start_time:
      this_file.extend(["0"]*(start_time - i))
    if type1 == "NON-LEX":
      if category == "other":
        # <no-speech> is taken as Silence
        this_file.extend(["0"]*duration)
      else:
        this_file.extend(["1"]*duration)
    if type1 == "LEXEME":
      this_file.extend(["2"]*duration)
    if type1 == "NON-SPEECH":
      this_file.extend(["1"]*duration)

  ref_file_handle.write(' '.join(this_file))
  ref_file_handle.close()

def read_class_file(class_file, reference, temp_dir):
  frame_diff = Analysis()

  per_file_diff = {}

  for line in class_file.readlines():
    splits = line.strip().split()
    file_id = splits[0]
    per_file_diff[file_id] = Analysis()
    if file_id not in reference:
      sys.stderr.write("Unknown fild ID " + file_id + "\n")
    try:
      this_file = open(temp_dir+"/"+file_id+".ref").readline().strip().split()[1:]
    except IOError:
      sys.stderr.write("Unable to open " + temp_dir+"/"+file_id+".ref\n")

    for i, prediction in enumerate(splits[1:]):
      if i < len(this_file):
        ref = this_file[i]
      else:
        ref = "0"
      if ref == "0" and prediction == "0":
        frame_diff.sil_as_sil += 1
        per_file_diff[file_id].sil_as_sil += 1
      elif ref == "0" and prediction == "1":
        frame_diff.sil_as_noise += 1
        per_file_diff[file_id].sil_as_noise += 1
      elif ref == "0" and prediction == "2":
        frame_diff.sil_as_speech += 1
        per_file_diff[file_id].sil_as_speech += 1
      elif ref == "1" and prediction == "0":
        frame_diff.noise_as_sil += 1
        per_file_diff[file_id].noise_as_sil += 1
      elif ref == "1" and prediction == "1":
        frame_diff.noise_as_noise += 1
        per_file_diff[file_id].noise_as_noise += 1
      elif ref == "1" and prediction == "2":
        frame_diff.noise_as_speech += 1
        per_file_diff[file_id].noise_as_speech += 1
      elif ref == "2" and prediction == "0":
        frame_diff.speech_as_sil += 1
        per_file_diff[file_id].speech_as_sil += 1
      elif ref == "2" and prediction == "1":
        frame_diff.speech_as_sil += 1
        per_file_diff[file_id].speech_as_sil += 1
      elif ref == "2" and prediction == "2":
        frame_diff.speech_as_speech += 1
        per_file_diff[file_id].speech_as_speech += 1
    while i < len(reference):
      if ref == "0":
        frame_diff.sil_as_sil += 1
        per_file_diff[file_id].sil_as_sil += 1
      elif ref == "1":
        frame_diff.noise_as_sil += 1
        per_file_diff[file_id].noise_as_sil += 1
      elif ref == "2":
        frame_diff.speech_as_sil += 1
        per_file_diff[file_id].speech_as_sil += 1

  frame_diff.compute_stats()
  frame_diff.write()
  for file_id in per_file_diff:
    sys.stdout.write("\n"+file_id+"\n")
    per_file_diff[file_id].compute_stats()
    per_file_diff[file_id].write()

if __name__ == '__main__':
  main()

