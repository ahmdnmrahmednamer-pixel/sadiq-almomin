"""Candidate index only. Never turns narrative mentions into verse attribution.

Retains original source offsets and full spans. Unmatched/ambiguous quotes are
reported, not copied to a neighbouring verse. A reviewed index is required
before application display. Inputs are source files, not model text.
"""
import argparse
import hashlib
import json
import re
import unicodedata


def normalize(text):
    text = text.translate(str.maketrans({'أ':'ا','إ':'ا','آ':'ا','ٱ':'ا','ى':'ي','ـ':''}))
    text = ''.join(c for c in text if not unicodedata.combining(c) and not '\u06d6' <= c <= '\u06ed')
    return ' '.join(re.findall(r'[\u0621-\u064a]+', text))


def build_index(source, surahs):
    names = {normalize(s['name']).removeprefix('سورة '):s['number'] for s in surahs}
    names.update({'براءة':9, 'الانفال':8, 'الاسراء او بني اسراييل':17,
                  'حم السجدة':41, 'ن':68, 'المعوذتين':113, 'الم نشرح لك':94})
    verses = {s['number']:[(a['numberInSurah'],normalize(a['text'])) for a in s['ayahs']] for s in surahs}
    # Only a printed chapter heading sets a surah. No inferred carry-over after
    # an unknown heading or an undivided joint-surah section.
    marks = list(re.finditer(r'^\s*سورة\s+([^\n]+?)\s*$',source,re.M))
    records=[]
    pages=list(re.finditer(r'الجزء:\s*(\d+)\s*¦\s*الصفحة:\s*(\d+)',source))
    for i,heading in enumerate(marks):
        name=normalize(heading.group(1))
        surah=names.get(name)
        end=marks[i+1].start() if i+1<len(marks) else len(source)
        quotes=list(re.finditer(r'قوله\s+تعال[ىي]\s+',source[heading.end():end]))
        for j,m in enumerate(quotes):
            start=heading.end()+m.start(); body_start=heading.end()+m.end()
            stop=heading.end()+quotes[j+1].start() if j+1<len(quotes) else end
            body=source[body_start:stop]
            # End of an explicit opening quotation. Narrator text is not used
            # to select a verse, even if it quotes another verse later.
            quote=re.split(r'الآية|الاية|الآيتين|الايتين|الآيات|الايات|\bأخرج\b|\bاخرج\b|\bروى\b|\bقال\b|\[|\n',body,maxsplit=1)[0].strip()
            q=normalize(re.sub(r'\([كص]\)', '', quote))
            candidates=[]
            if surah and name!='المعوذتين' and len(q.split())>=3:
                candidates=[n for n,t in verses.get(surah,[]) if (' '+q+' ') in (' '+t+' ')]
            status='unique' if len(candidates)==1 else 'ambiguous' if candidates else 'unmatched'
            # A printed page marker follows that page's text in Shamela exports.
            page=next((p for p in pages if p.start()>=start),None)
            records.append({'surah':surah,'candidates':candidates,'status':status,
                'quote':quote,'start':start,'end':stop,
                'part':int(page.group(1)) if page else None,
                'page':int(page.group(2)) if page else None,
                'span_sha256':hashlib.sha256(source[start:stop].encode()).hexdigest()})
    return {'source_sha256':hashlib.sha256(source.encode()).hexdigest(),
            'reviewed':False,'records':records}


def main():
    p=argparse.ArgumentParser();p.add_argument('--source-path',required=True);p.add_argument('--quran-path',required=True);p.add_argument('--output',required=True);a=p.parse_args()
    source=open(a.source_path,encoding='utf-8').read();quran=json.load(open(a.quran_path,encoding='utf-8'))
    result=build_index(source,quran['data']['surahs'])
    with open(a.output,'w',encoding='utf-8') as f:json.dump(result,f,ensure_ascii=False,indent=2)
    print(json.dumps({s:sum(r['status']==s for r in result['records']) for s in ['unique','ambiguous','unmatched']}))
if __name__=='__main__':main()
