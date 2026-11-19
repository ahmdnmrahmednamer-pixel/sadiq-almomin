"""Build a metadata-only verse index. Religious text remains at its live source.

Match explicit opening quotations only. Unknown headings, short quotations and
ambiguous matches stay in the audit, never become display records. Every page
must independently match the printed-page export before a page is credited.
"""
import argparse, bisect, hashlib, json, re
from html.parser import HTMLParser
from index_explicit_verse_quotes import normalize

class Plain(HTMLParser):
    def __init__(self): super().__init__(); self.out=[]
    def handle_starttag(self, tag, attrs):
        if tag in ('br','p'): self.out.append('\n')
    def handle_endtag(self, tag):
        if tag=='p': self.out.append('\n')
    def handle_data(self, data): self.out.append(data)

def plain(text):
    p=Plain();p.feed(text);return ''.join(p.out).replace('\r','\n')
def comparable(text):
    return normalize(plain(text).replace('ﷺ','صلى الله عليه وسلم'))
def build(data, printed, quran):
    pages={};start=0
    for m in re.finditer(r'الجزء:\s*(\d+)\s*¦\s*الصفحة:\s*(\d+)',printed):
        pages[int(m[2])]=comparable(printed[start:m.start()]);start=m.end()
    chunks=[];text=''
    for c in data['contents']:
        norm=comparable(c['text'])
        matches=[n for n,t in pages.items() if norm==t or (' '+norm+' ') in (' '+t+' ')]
        if len(matches)!=1: raise ValueError('Printed page unresolved: '+str(c['id']))
        content=plain(c['text']);begin=len(text);text+=content+'\n'
        chunks.append({'id':c['id'],'page':matches[0],'start':begin,'end':begin+len(content),
            'sha256':hashlib.sha256(c['text'].encode()).hexdigest()})
    names={normalize(s['name']).removeprefix('سورة '):s['number'] for s in quran}
    aliases={'براءة':9,'الاسراء او بني اسرائيل':17,'فاطر او الملائكة':35,
             'حم السجدة':41,'ن او القلم':68,'الم نشرح لك':94}
    names.update({normalize(k):v for k,v in aliases.items()})
    headings=list(re.finditer(r'^\s*سورة\s+([^\n]+?)\s*$',text,re.M))
    records=[];audit=[]
    for i,h in enumerate(headings):
        name=normalize(h[1]);surah=names.get(name)
        end=headings[i+1].start() if i+1<len(headings) else len(text)
        marks=list(re.finditer(r'قوله\s+تعال[ىي]\s+',text[h.end():end]))
        for j,m in enumerate(marks):
            a=h.end()+m.start();b=h.end()+marks[j+1].start() if j+1<len(marks) else end
            body=text[h.end()+m.end():b]
            quote=re.split(r'الآية|الاية|الآيتين|الايتين|الآيات|الايات|\bأخرج\b|\bاخرج\b|\bروى\b|\bقال\b|\[|\n',body,maxsplit=1)[0].strip()
            norm=normalize(re.sub(r'\([كص]\)','',quote))
            matches=[]
            if surah and len(norm.split())>=3:
                verses=quran[surah-1]['ayahs']
                matches=[v['numberInSurah'] for v in verses if (' '+norm+' ') in (' '+normalize(v['text'])+' ')]
            row={'surah':surah,'candidates':matches,'quote':quote,'start':a,'end':b}
            audit.append(row)
            if len(matches)!=1: continue
            # Offsets index Unicode scalar values, decoded as runes in Dart.
            segments=[]
            for c in chunks:
                lo=max(a,c['start']);hi=min(b,c['end'])
                if hi>lo:segments.append({'id':c['id'],'from':lo-c['start'],'to':hi-c['start']})
            records.append({'surah':surah,'ayah':matches[0],'segments':segments})
    return {'provider':'quranpedia.net','bookId':69,'sourceUrl':'https://api.quranpedia.net/books-contents/book-69.json',
            'checkedAt':'2026-11-19','licenseVersion':'2026-11-17',
            'pages':[{k:v for k,v in c.items() if k not in ('start','end')} for c in chunks if c['id'] in {s['id'] for r in records for s in r['segments']}],
            'verifiedPageCount':len(chunks),'linkType':'explicit_heading_quote',
            'reviewed':False,'navigationOnly':True,'scope':'source-entry-not-a-single-narration',
            'credit':'Quranpedia.net','records':records},audit

def main():
    p=argparse.ArgumentParser();p.add_argument('--source',required=True);p.add_argument('--printed',required=True);p.add_argument('--quran',required=True);p.add_argument('--output',required=True);p.add_argument('--audit',required=True);a=p.parse_args()
    result,audit=build(json.load(open(a.source)),open(a.printed).read(),json.load(open(a.quran))['data']['surahs'])
    json.dump(result,open(a.output,'w'),ensure_ascii=False,separators=(',',':'));json.dump(audit,open(a.audit,'w'),ensure_ascii=False,indent=2)
    print('verified pages',len(result['pages']),'unique records',len(result['records']),'unresolved',len(audit)-len(result['records']))
if __name__=='__main__':main()
