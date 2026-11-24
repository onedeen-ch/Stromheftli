"""Exercise the installed APK through Android's picker, share and offline PDF viewer."""
import io
import re
import subprocess
import time
import zipfile
from xml.etree import ElementTree as ET

PKG = "ch.stromheftli.app"
ACTIVITY = PKG + "/.MainActivity"

def adb(*args, data=None):
    return subprocess.run(["adb", *args], input=data, capture_output=True, check=True).stdout

def shell(*args):
    return adb("shell", *args).decode(errors="replace")

def ui():
    shell("uiautomator", "dump", "/sdcard/inspector.xml")
    return ET.fromstring(adb("exec-out", "cat", "/sdcard/inspector.xml"))

def find(label, timeout=40, tap=False, prefix=False):
    deadline = time.monotonic() + timeout
    visible = []
    while time.monotonic() < deadline:
        try:
            tree = ui()
            visible = []
            for n in tree.iter("node"):
                labels = [n.get("text", ""), n.get("content-desc", "")]
                visible.extend(s for s in labels if s)
                if any(v.casefold() == label.casefold() or label in v.splitlines() or (prefix and v.startswith(label)) for v in labels):
                    if tap:
                        x1,y1,x2,y2 = map(int,re.findall(r"\d+",n.get("bounds")))
                        shell("input","tap",str((x1+x2)//2),str((y1+y2)//2))
                    return True
        except ET.ParseError:
            pass
        time.sleep(.5)
    raise AssertionError(f"{label!r} fehlt. Sichtbar: {visible}")

def touch(label, **kwargs):
    find(label,tap=True,**kwargs)

def document(name, mime, data):
    collection = "content://media/external/downloads"
    shell("content","insert","--uri",collection,"--bind","_display_name:s:"+name,
          "--bind","mime_type:s:"+mime,"--bind","relative_path:s:Download/")
    rows = shell("content","query","--uri",collection,"--projection","_id:_display_name")
    row = next(l for l in rows.splitlines() if name in l)
    uri = collection + "/" + re.search(r"_id=(\d+)",row)[1]
    adb("shell","content","write","--uri",uri,data=data)
    return uri

def sample_xlsx():
    data=io.BytesIO()
    with zipfile.ZipFile(data,"w",zipfile.ZIP_DEFLATED) as z:
        z.writestr("xl/workbook.xml",'<workbook xmlns:r="urn:r"><sheets><sheet r:id="sheet1"/></sheets></workbook>')
        z.writestr("xl/_rels/workbook.xml.rels",'<Relationships><Relationship Id="sheet1" Target="worksheets/sheet1.xml"/></Relationships>')
        rows=[["Datum","Zeit","Wirkleistung [kW]"],["01.10.2026","00:15:00","1.124"],
              ["01.10.2026","00:30:00","2.252"],["01.10.2026","00:45:00","1.04"],["01.10.2026","01:00:00","1.144"]]
        xml=[]
        for i,row in enumerate(rows,1):
            cells="".join(f'<c r="{col}{i}" t="inlineStr"><is><t>{val}</t></is></c>' for col,val in zip("ABC",row))
            xml.append(f'<row r="{i}">{cells}</row>')
        z.writestr("xl/worksheets/sheet1.xml","<worksheet><sheetData>"+"".join(xml)+"</sheetData></worksheet>")
    return data.getvalue()

def sample_pdf():
    data=bytearray(b"%PDF-1.4\n")
    offsets=[]
    objects=["<< /Type /Catalog /Pages 2 0 R >>","<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
             "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Resources << >> /Contents 4 0 R >>",
             "<< /Length 0 >>\nstream\n\nendstream"]
    for i,obj in enumerate(objects,1):
        offsets.append(len(data))
        data.extend(f"{i} 0 obj\n{obj}\nendobj\n".encode())
    start=len(data)
    data.extend(b"xref\n0 5\n0000000000 65535 f \n")
    for pos in offsets:
        data.extend(f"{pos:010} 00000 n \n".encode())
    data.extend(f"trailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n{start}\n%%EOF\n".encode())
    return data

def main():
    shell("am","start","-n",ACTIVITY)
    find("Lastgang importieren",prefix=True)
    document("lastgang.xlsx","application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",sample_xlsx())
    touch("Lastgang importieren",prefix=True)
    try:
        touch("lastgang.xlsx",timeout=8)
    except AssertionError:
        touch("Show roots",timeout=10)
        touch("Downloads")
        touch("lastgang.xlsx")
    touch("Import bestätigen")
    find("1.39 kWh")
    print("XLSX import via DocumentsUI confirmed",flush=True)
    document("september.csv","text/csv","Datum;Zeit;Energie [kWh]\n01.09.2026;07:00;1,25\n02.09.2026;07:15;2,75\n".encode())
    touch("Verbrauch",prefix=True)
    touch("Lastgang importieren",prefix=True)
    try:
        touch("september.csv",timeout=8)
    except AssertionError:
        touch("Show roots",timeout=10)
        touch("Downloads")
        touch("september.csv")
    find("HT 2.75 kWh · NT 1.25 kWh")
    touch("Import bestätigen")
    find("4 kWh")
    find("HT 2.75 kWh · NT 1.25 kWh")
    print("CSV, Intervallenergie und HT/NT im importierten Monat bestätigt",flush=True)
    pdf=document("rechnung.pdf","application/pdf",sample_pdf())
    # adb sends the raw intent straight to ActivityManager. A regular sharing app
    # supplies ClipData for the grant. Include the same URI as data for adb.
    print(shell("am","start","-W","-n",ACTIVITY,"-a","android.intent.action.SEND",
                "-d",pdf,"-t","application/pdf","--eu","android.intent.extra.STREAM",pdf,
                "--grant-read-uri-permission"),flush=True)
    touch("Rechnung speichern")
    shell("content","delete","--uri",pdf)
    shell("am","force-stop",PKG)
    shell("svc","wifi","disable")
    shell("svc","data","disable")
    shell("am","start","-n",ACTIVITY)
    find("1.39 kWh")
    touch("Rechnungen",prefix=True)
    # Bill's month depends on the emulator clock.
    month=int(shell("date","+%m").strip())
    names="Januar Februar März April Mai Juni Juli August September Oktober November Dezember".split()
    touch(names[month-1],prefix=True)
    find("Rechnungsseite")
    find("Weiter")
    print("Cold restart, shared PDF copy and native offline rendering confirmed",flush=True)

if __name__=="__main__":
    try:
        main()
    except Exception:
        print(shell("logcat","-d","-t","550"),flush=True)
        raise
