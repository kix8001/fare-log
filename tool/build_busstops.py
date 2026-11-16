import re, glob, gzip, sys
out_path = sys.argv[2]
stops = []
for f in sorted(glob.glob(sys.argv[1] + '/*/P11-22_*.xml')):
    s = open(f, encoding='utf-8').read()
    pts = dict(re.findall(r'<gml:Point gml:id="(n\d+)">\s*<gml:pos>([\d.]+ [\d.]+)</gml:pos>', s))
    for m in re.finditer(r'<ksj:BusStop gml:id="[^"]+">(.*?)</ksj:BusStop>', s, re.S):
        b = m.group(1)
        ref = re.search(r'xlink:href="#(n\d+)"', b).group(1)
        name = re.search(r'<ksj:bsn>(.*?)</ksj:bsn>', b).group(1).strip()
        ops = []
        for o in re.findall(r'<ksj:boc>(.*?)</ksj:boc>', b):
            o = o.strip()
            if o and o not in ops: ops.append(o)
        lat, lng = map(float, pts[ref].split())
        stops.append((round(lat * 1e5), round(lng * 1e5), name.replace('\t', ' '), '・'.join(ops[:2]).replace('\t', ' ')))
stops.sort()
optab = {}
lines = []
for la, lo, n, op in stops:
    i = optab.setdefault(op, len(optab))
    lines.append(f'{la}\t{lo}\t{n}\t{i}')
body = '#ops\n' + '\n'.join(optab.keys()) + '\n#stops\n' + '\n'.join(lines) + '\n'
with gzip.open(out_path, 'wb', 9) as g:
    g.write(body.encode('utf-8'))
print(len(stops), 'stops', len(optab), 'operators')
