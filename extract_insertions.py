import sys, re

segments_file = None
if len(sys.argv) == 3:
  segments_file = sys.argv[2]
elif len(sys.argv) != 2:
  sys.exit(1)
sgml_file = sys.argv[1]

sgml_file_handle = open(sgml_file)
if segments_file != None:
  segments_handle = open(segments_file)
  line = segments_handle.readline()
  seg_utt_id, seg_file_id, seg_s, seg_e = line.strip().split()
  seg_s = float(seg_s)
  seg_e = float(seg_e)

lengths = []
locations = []
lines = sgml_file_handle.readlines()
insertions = {}
insertion_lengths = {}
insertion_lengths["ALL"] = []
substitutions = {}
substitution_lengths = {}
substitution_lengths["ALL"] = []
for l in lines:
  m = re.search(r"file=\"(?P<file_id>\w+)\"",l)
  if m:
    file_id = m.group('file_id')
    continue
  m = re.findall(r"(?:^|:)(?P<insertion>(?:(?:I,.*?)|(?:S,\"<.*?)))(?::|$)", l)

  if len(m) > 0:
    for a in m:
      b = a.split(',')
      s,e = float(b[3].split('+')[0]), float(b[3].split('+')[1])
      while segments_file != None and (seg_file_id < file_id or seg_e < s):
        line = segments_handle.readline()
        seg_utt_id, seg_file_id, seg_s, seg_e = line.strip().split()
        seg_s = float(seg_s)
        seg_e = float(seg_e)
      if segments_file == None or (seg_file_id == file_id and seg_s > e):
        if b[1] != "":
          locations.append("%50s: %10f %10f %10f %s S(%s)" % (file_id, s, e, e-s, b[2], b[1]))
          substitutions[b[2]] = substitutions.get(b[2],0) + 1
          substitution_lengths.setdefault(b[2],[])
          substitution_lengths[b[2]].append(e-s)
          substitutions["ALL"] = substitutions.get("ALL",0) + 1
          substitution_lengths["ALL"].append(e-s)
        else:
          locations.append("%50s: %10f %10f %10f %s" % (file_id, s, e, e-s, b[2]))
          insertions[b[2]] = insertions.get(b[2],0) + 1
          insertion_lengths.setdefault(b[2],[])
          insertion_lengths[b[2]].append(e-s)
          insertions["ALL"] = insertions.get("ALL",0) + 1
          insertion_lengths["ALL"].append(e-s)

if segments_file != None:
  segments_handle.close()
sgml_file_handle.close()
print("Count\tWord\tAverage length")
stats = sorted([ (insertions[w], w,sum(insertion_lengths[w])/len(insertion_lengths[w])) for w in insertions ], key=lambda x:x[0], reverse=True)
for w in stats:
  print("%5d\t%s\t\t%f" % w)
stats = sorted([ (substitutions[w], w,sum(substitution_lengths[w])/len(substitution_lengths[w])) for w in substitutions ], key=lambda x:x[0], reverse=True)
for w in stats:
  print("%5d\t%s\t\t%f" % w)

print("\nInsertion Locations: ")
for w in locations:
  print("%s" % w)

