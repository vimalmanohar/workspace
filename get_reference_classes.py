#!/usr/bin/python

import argparse, sys, os
from argparse import ArgumentParser

def main():
  parser = ArgumentParser(description='Convert force alignment output to reference classes')
  parser.add_argument('-p', '--prefix', type=str, dest='prefix', \
      help = "The prefix for the file id" \
      + "\ne.g. BABEL_BP_102")
  parser.add_argument('args', nargs=2, help='<force_align_file> <output_dir>')
  parser.add_argument('-s', '--frame-shift', \
      dest='frame_shift', default=0.01, type=float, help="Frame shift in seconds")
  parser.add_argument('-a', '--align', \
      dest='align', action='store_true', help="Alignments not class")
  options = parser.parse_args()

  force_align_file = options.args[0]
  output_dir = options.args[1]

  if force_align_file == "-":
    read_alignments(sys.stdin, output_dir, options)
  else:
    read_alignments(open(force_align_file), output_dir, options)

def read_alignments(force_align_file, output_dir, options):
  reference = {}
  for line in force_align_file.readlines():
    splits = line.strip().split()

    orig_file_id = splits[0]
    temp = orig_file_id.split('_')
    if options.prefix != None:
      file_id = options.prefix + '_' + '_'.join([temp[0]] + temp[2:-1])
      if temp[1] == 'A':
        file_id += "_inLine"
      else:
        file_id += "_outLine"
    else:
      file_id = '_'.join(temp[0:-1])

    if file_id not in reference:
      reference[file_id] = []

    start_time = int(temp[-1])
    if len(reference[file_id]) < start_time:
      if options.align:
        reference[file_id].extend(["SIL"]*(start_time - len(reference[file_id])))
      else:
        reference[file_id].extend(["0"]*(start_time - len(reference[file_id])))
    reference[file_id].extend(splits[1:])

  for file_id in reference:
    file_path = output_dir+"/"+file_id+".ref"
    try:
      file_handle = open(file_path, 'w')
    except IOError:
      sys.stderr.write("Unable to open file " + file_path + "\n")
      sys.exit(1)
    file_handle.write(file_id + " " + ' '.join(reference[file_id])+"\n")
    file_handle.close()

if __name__ == '__main__':
  main()
