from pathlib import Path
# Lexically check bracket balance, Dart comments and quoted strings (incl. ${...})
# Note: this is not a Dart parser or compiler.

def check(code, filename):
    stack=[]; i=0; state='code'; quote=''; triple=False; nested=0
    while i<len(code):
        ch=code[i]; nxt=code[i+1] if i+1<len(code) else ''
        if state=='code':
            if ch=='/' and nxt=='/':state='line';i+=2;continue
            if ch=='/' and nxt=='*':state='block';nested=1;i+=2;continue
            if ch in ('"',"'"):
                triple=code[i:i+3]==ch*3; quote=ch;state='string';i+=3 if triple else 1;continue
            if ch in '([{':stack.append((ch,i))
            elif ch in ')]}':
                if not stack or '([{'.index(stack[-1][0])!=')]}'.index(ch):
                    return f'{filename}: mismatch {ch} at {i}, previous={stack[-1] if stack else None}, line {code[:i].count(chr(10))+1}'
                stack.pop()
            i+=1;continue
        if state=='line':
            if ch=='\n':state='code'
            i+=1;continue
        if state=='block':
            if ch=='/' and nxt=='*':nested+=1;i+=2;continue
            if ch=='*' and nxt=='/':nested-=1;i+=2;state='code' if nested==0 else 'block';continue
            i+=1;continue
        if state=='string':
            if ch=='\\':i+=2;continue
            if triple and code[i:i+3]==quote*3:state='code';i+=3;continue
            if not triple and ch==quote:state='code';i+=1;continue
            i+=1;continue
    if stack:
        return f'{filename}: OPEN {stack[-1][0]} at line {code[:stack[-1][1]].count(chr(10))+1}, count {len(stack)}'
    if state in ('block','string'):return f'{filename}: unclosed {state}'
    return None


if __name__ == '__main__':
    import os, sys, struct, xml.etree.ElementTree as ET
    root = Path(__file__).resolve().parents[1]
    failure = []
    for f in sorted(root.rglob('*.dart')):
        e = check(f.read_text(encoding='utf-8'), f.relative_to(root))
        if e: failure.append(str(e))
    png_sizes = {
        'mipmap-mdpi': (48,48), 'mipmap-hdpi': (72,72),
        'mipmap-xhdpi': (96,96), 'mipmap-xxhdpi': (144,144),
        'mipmap-xxxhdpi': (192,192),
    }
    res = root/'android/app/src/main/res'
    for folder,size in png_sizes.items():
        f = res/folder/'ic_launcher.png'
        if not f.exists(): failure.append(f'Missing icon {f}')
        else:
            data = f.read_bytes()
            if data[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II',data[16:24]) != size:
                failure.append(f'Invalid PNG dimensions {f}')
    for f in res.rglob('*.xml'):
        try: ET.parse(f)
        except Exception as e: failure.append(f'{f}: {e}')
    try: ET.parse(root/'android/app/src/main/AndroidManifest.xml')
    except Exception as e: failure.append(f'AndroidManifest.xml: {e}')
    assert (root/'pubspec.yaml').exists()
    assert (root/'lib/main.dart').exists()
    assert (root/'assets/branding/blousab_reference_logo.png').exists()
    print(f'STATIC_DART_BALANCE={"PASS" if not failure else "FAIL"}; DART_FILES={len(list(root.rglob("*.dart")))}')
    print(f'ICON_AND_XML={"PASS" if not failure else "FAIL"}')
    for err in failure: print('FAIL:',err)
    print('NOTE: static check is NOT a Dart compiler; run Flutter analyze/build too.')
    sys.exit(1 if failure else 0)
