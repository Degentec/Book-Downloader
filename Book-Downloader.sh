#!/usr/bin/env bash
# ============================================================
#  Book-Downloader  （原《小说下载器》改名 + 加水印/防篡改）
#
#  该软件直间执事原创，QQ交流1018048391，禁止贩卖商用！
#
#  数据源: bqg876.cc / apibi.cc（搜索走公开 HTTP，正文走无头浏览器内嵌钩子）
#  用法:   ./Book-Downloader [书名]
#  跨发行版: 自动识别 Arch / Debian系 / Fedora系 / SUSE / Gentoo / Void / Alpine，
#           并按各家包管理自动安装依赖（未知发行版用 pip 兜底）。
#  防篡改: 每次运行做 SHA-256 自校验，魔改即拒绝运行。
# ============================================================

readonly WATERMARK="该软件直间执事原创，QQ交流1018048391，禁止贩卖商用！"
readonly WMBAR="==================================================================="

wmmark() {
    printf '%s\n' "$WMBAR"
    printf '%s\n' "  Book-Downloader —— $WATERMARK"
    printf '%s\n' "  原创声明见文件头；每次运行强制完整性自校验。"
    printf '%s\n' "$WMBAR"
}

# ====INTEGRITY-BEGIN====
# SELFHASH=bc65b9bbe2682bfcf29fca2f770868699497ecd22cb027506782107920d75ce3
# ====INTEGRITY-END====

selfcheck() {
    local self="$0"
    [ -f "$self" ] || return 1
    local tmp calc exp
    tmp="$(mktemp)" || return 1
    sed "s/^# SELFHASH=.*/# SELFHASH=0/" "$self" | sha256sum | awk '{print $1}' > "$tmp"
    calc="$(cat "$tmp")"; rm -f "$tmp"
    exp="$(grep -oP '^# SELFHASH=\K.*' "$self" | head -1)"
    [ -n "$exp" ] && [ "$calc" = "$exp" ]
}

wmmark
if ! selfcheck; then
    printf '%s\n' "$WMBAR"
    printf '%s\n' "  ✖ 完整性校验失败：文件已被篡改！"
    printf '%s\n' "  $WATERMARK"
    printf '%s\n' "  本软件拒绝继续运行，请从可信来源重新获取原版。"
    printf '%s\n' "$WMBAR"
    exit 1
fi
printf '%s\n' "  ✔ 完整性校验通过（SHA-256 一致）。"

set -uo pipefail

detect_os() {
    local id
    if [ -r /etc/os-release ]; then
        id="$(grep -oP '^ID=\K.*' /etc/os-release 2>/dev/null | tr -d '"' | head -1)"
    fi
    case "$id" in
        arch|manjaro|endeavouros|artix|cachyos|garuda)          family=arch ;;
        debian|ubuntu|linuxmint|pop|kali|elementary|zorin)      family=debian ;;
        fedora|centos|rhel|rocky|almalinux|nobara)              family=fedora ;;
        opensuse*|suse)                                         family=suse ;;
        gentoo)                                                 family=gentoo ;;
        void)                                                   family=void ;;
        alpine)                                                 family=alpine ;;
        *)                                                      family=unknown ;;
    esac
}

need_py()  { command -v python3 >/dev/null 2>&1; }
need_sel() { python3 -c 'import selenium' >/dev/null 2>&1; }
need_brw() {
    command -v chromium          >/dev/null 2>&1 ||
    command -v chromium-browser  >/dev/null 2>&1 ||
    command -v google-chrome     >/dev/null 2>&1 ||
    command -v microsoft-edge    >/dev/null 2>&1 || return 1
}

install_deps() {
    local missing=()
    need_py || missing+=("python3")
    need_sel || missing+=("selenium")
    need_brw || missing+=("browser(chromium/chrome)")

    if [ ${#missing[@]} -eq 0 ]; then
        return 0
    fi

    echo "缺少依赖: ${missing[*]}"
    detect_os
    echo "已识别发行版: $family"

    case "$family" in
        arch)
            echo "→ 使用 pacman 安装 chromium + python-selenium ..."
            sudo pacman -S --needed --noconfirm chromium python-selenium >/dev/null 2>&1 ;;
        debian)
            echo "→ 使用 apt 安装 chromium-driver + python3-selenium ..."
            sudo apt-get update -qq >/dev/null 2>&1
            sudo apt-get install -y --no-install-recommends chromium-driver python3-selenium >/dev/null 2>&1 ;;
        fedora)
            echo "→ 使用 dnf 安装 chromium + python3-selenium ..."
            sudo dnf install -y chromium python3-selenium >/dev/null 2>&1 ;;
        suse)
            echo "→ 使用 zypper 安装 chromium + python3-selenium ..."
            sudo zypper --non-interactive install chromium python3-selenium >/dev/null 2>&1 ;;
        gentoo)
            echo "→ 使用 emerge 安装 chromium + dev-python/selenium ..."
            sudo emerge --ask=n -q chromium dev-python/selenium >/dev/null 2>&1 ;;
        void)
            echo "→ 使用 xbps 安装 chromium + python3-selenium ..."
            sudo xbps-install -Sy chromium python3-selenium >/dev/null 2>&1 ;;
        alpine)
            echo "→ 使用 apk 安装 chromium + chromium-chromedriver + py3-selenium ..."
            sudo apk add --no-cache chromium chromium-chromedriver py3-selenium >/dev/null 2>&1 ;;
        *)
            echo "未识别的发行版（family=$family），尝试用 pip 补装 selenium ..."
            ;;
    esac

    # 兜底：只要 python3 可用，就用 pip 补装 selenium（兼容 PEP 668 的 --break-system-packages）
    if need_py && ! need_sel; then
        python3 -m pip install --user --break-system-packages selenium >/dev/null 2>&1
    fi

    local still=()
    need_py || still+=("python3")
    need_sel || still+=("python-selenium")
    need_brw || still+=("chromium/chrome 浏览器")
    if [ ${#still[@]} -gt 0 ]; then
        echo "仍缺依赖: ${still[*]}"
        echo "请手动安装后重试；若你已自行准备好环境，可设置 SKIP_DEPS_CHECK=1 强制运行。"
        [ "${SKIP_DEPS_CHECK:-0}" = "1" ] && return 0
        exit 1
    fi
}

check_deps() {
    if [ "${SKIP_DEPS_CHECK:-0}" = "1" ]; then
        echo "SKIP_DEPS_CHECK=1，跳过依赖检查。"
        need_py || { echo "缺少 python3，无法运行。"; exit 1; }
        return 0
    fi
    install_deps
}

check_deps

QUERY="${1:-}"

PYFILE="$(mktemp /tmp/lqxs_XXXXXX.py)"
trap 'rm -f "$PYFILE"' EXIT

cat > "$PYFILE" <<'PYEOF'
# -*- coding: utf-8 -*-
import sys, os, re, json, time, signal, termios, tty, urllib.request, urllib.parse

WATERMARK = "该软件直间执事原创，QQ交流1018048391，禁止贩卖商用！"
WMBAR = "=" * 66

BASE = "https://www.bqg876.cc/"
API  = "https://apibi.cc"
UA   = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
QUERY = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else ""

def http_json(url, timeout=25):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Referer": BASE, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", "replace"))

def search(q):
    try:
        d = http_json(API + "/api/search?q=" + urllib.parse.quote(q))
        return d.get("data") or []
    except Exception as e:
        print("搜索失败:", e)
        return []

# ---------- 交互菜单（方向键选择） ----------
def ask_query():
    if QUERY:
        return QUERY
    print("输入书名（直接回车退出）:", end=" ", flush=True)
    try:
        q = input().strip()
    except EOFError:
        q = ""
    sys.stdout.write("\n")
    return q

def pick(items):
    if not items:
        print("没有找到相关书籍。")
        return None
    n = len(items)
    if not sys.stdin.isatty():
        # 非交互环境：改用数字选择
        print("（非交互模式，输入数字选择 1-%d，0 退出）" % n)
        for i, it in enumerate(items):
            print(" %2d  %s - %s" % (i + 1, it.get("title", ""), it.get("author", "")))
        try:
            s = input().strip()
        except EOFError:
            s = ""
        if s.isdigit():
            k = int(s)
            if 1 <= k <= n:
                return items[k - 1]
        return None
    idx, old = 0, termios.tcgetattr(sys.stdin.fileno())
    try:
        tty.setcbreak(sys.stdin.fileno())
        while True:
            os.system("clear")
            print("  请用 ↑/↓ 选择书籍，回车确认，q 退出（共 %d 本）\n" % n)
            for i, it in enumerate(items):
                mark = ">" if i == idx else " "
                t = it.get("title", "")
                a = it.get("author", "")
                print(" %s %-2d %s - %s" % (mark, i + 1, t, a))
            sys.stdout.flush()
            ch = sys.stdin.read(1)
            if ch == "\x1b":
                seq = sys.stdin.read(2)
                if seq == "[A":
                    idx = (idx - 1) % n
                elif seq == "[B":
                    idx = (idx + 1) % n
            elif ch in ("\r", "\n"):
                break
            elif ch in ("q", "Q"):
                return None
            elif ch.isdigit():
                num = int(ch)
                if 1 <= num <= n:
                    idx = num - 1
    finally:
        termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, old)
    sys.stdout.write("\n")
    return items[idx]

# ---------- 无头浏览器下载 ----------
HOOK = r"""
window.__cap = window.__cap || {};
var _open_ = XMLHttpRequest.prototype.open;
var _send_ = XMLHttpRequest.prototype.send;
XMLHttpRequest.prototype.open = function(m, u){ this.__u = String(u); return _open_.apply(this, arguments); };
XMLHttpRequest.prototype.send = function(){
  var self = this;
  if (self.__u && (/\/api\/chapter/.test(self.__u) || /\/api\/booklist/.test(self.__u))) {
    self.addEventListener('load', function(){
      try {
        var d = JSON.parse(self.responseText);
        if (d && d.chapterid !== undefined) window.__cap['ch:'+d.chapterid] = self.responseText;
        else if (d && d.list) window.__cap['list'] = self.responseText;
      } catch(e){}
    });
  }
  return _send_.apply(this, arguments);
};
var _f_ = window.fetch;
window.fetch = function(){
  var args = arguments;
  return _f_.apply(this, args).then(function(r){
    if (args[0] && (/\/api\/chapter/.test(args[0]) || /\/api\/booklist/.test(args[0]))) {
      return r.clone().text().then(function(t){
        try { var d = JSON.parse(t);
          if (d && d.chapterid !== undefined) window.__cap['ch:'+d.chapterid] = t;
          else if (d && d.list) window.__cap['list'] = t;
        } catch(e){}
        return r;
      });
    }
    return r;
  });
};
"""

import warnings
warnings.filterwarnings("ignore")

def find_browser():
    from shutil import which
    for c in ("chromium", "chromium-browser", "google-chrome", "google-chrome-stable",
              "microsoft-edge", "microsoft-edge-stable", "brave-browser", "vivaldi"):
        p = which(c)
        if p:
            return p
    return None

def find_driver():
    from shutil import which
    for c in ("chromedriver", "chromium-driver"):
        p = which(c)
        if p:
            return p
    for c in ("/usr/lib/chromium/chromedriver", "/usr/lib/chromium-browser/chromedriver",
              "/usr/bin/chromedriver", "/usr/lib/chrome/chromedriver"):
        if os.path.exists(c):
            return c
    return None

def open_browser():
    from selenium import webdriver
    m = re.match(r"(\d+)", getattr(webdriver, "__version__", "") or "")
    sel_major = int(m.group(1)) if m else 4

    opts = webdriver.ChromeOptions()
    browser_bin = os.environ.get("CHROME_BIN") or find_browser()
    drv_path = os.environ.get("CHROMEDRIVER") or find_driver()
    if browser_bin:
        opts.binary_location = browser_bin
    opts.add_argument("--headless")
    opts.add_argument("--no-sandbox")
    opts.add_argument("--disable-gpu")
    opts.add_argument("--disable-dev-shm-usage")
    opts.add_argument("--log-level=3")

    if sel_major >= 4:
        if drv_path:
            from selenium.webdriver.chrome.service import Service
            drv = webdriver.Chrome(options=opts, service=Service(executable_path=drv_path))
        else:
            # selenium >= 4.6 的 Selenium Manager 会自动下载匹配的 driver
            drv = webdriver.Chrome(options=opts)
    else:
        if drv_path:
            drv = webdriver.Chrome(executable_path=drv_path, chrome_options=opts)
        else:
            drv = webdriver.Chrome(chrome_options=opts)

    drv.set_page_load_timeout(60)
    drv.execute_cdp_cmd("Page.addScriptToEvaluateOnNewDocument", {"source": HOOK})
    return drv

def get_booklist(drv, bookid):
    drv.get(BASE + "#/book/%s/" % bookid)
    time.sleep(8)
    lst = drv.execute_script("return window.__cap['list'] || null;")
    for _ in range(20):
        if lst:
            try:
                titles = json.loads(lst)["list"]
                if titles:
                    return titles
            except Exception:
                pass
        time.sleep(1)
        lst = drv.execute_script("return window.__cap['list'] || null;")
    return None

def download_book(book, outdir):
    bookid = book["id"]
    title = re.sub(r'[\\/:*?"<>|]', "_", book["title"])
    tmpdir = os.path.join(outdir, ".%s_%s.lqxs" % (title, bookid))
    os.makedirs(tmpdir, exist_ok=True)
    done = set()
    for fn in os.listdir(tmpdir):
        if fn.endswith(".json"):
            try:
                done.add(int(fn[:-5]))
            except ValueError:
                pass

    drv = open_browser()
    try:
        titles = get_booklist(drv, bookid)
        if not titles:
            print("获取章节列表失败。")
            return False
        N = len(titles)
        print("《%s》 共 %d 章，已下载 %d 章，开始下载..." % (book["title"], N, len(done)))
        os.makedirs(tmpdir, exist_ok=True)

        def flush():
            cap = drv.execute_script("return window.__cap;")
            for k, v in list(cap.items()):
                if k.startswith("ch:"):
                    cid = int(k[3:])
                    if cid not in done:
                        try:
                            d = json.loads(v)
                            title_h = d.get("chaptername", "")
                            txt = d.get("txt", "")
                            if txt.strip():
                                with open(os.path.join(tmpdir, "%06d.json" % cid), "w", encoding="utf-8") as f:
                                    json.dump({"n": cid, "t": title_h, "b": txt}, f, ensure_ascii=False)
                                done.add(cid)
                        except Exception:
                            pass
                elif k == "list":
                    pass

        # 主下载循环：逐章切换 hash，页面自动发请求，钩子捕获响应
        delay = float(os.environ.get("LQXS_DELAY", "0.45"))
        for cid in range(1, N + 1):
            if cid in done:
                continue
            drv.execute_script("location.hash='/book/%s/%d.html'" % (bookid, cid))
            time.sleep(delay)
            if cid % 20 == 0 or cid == 1:
                flush()
                sys.stdout.write("\r  进度 %d/%d" % (len(done), N))
                sys.stdout.flush()
        flush()
        sys.stdout.write("\r  进度 %d/%d\n" % (len(done), N))
        sys.stdout.flush()

        # 校验与补抓：逐一确认缺失章节
        missing = [c for c in range(1, N + 1) if c not in done]
        if missing:
            print("校验发现缺失 %d 章，补抓中..." % len(missing))
            for cid in missing:
                for attempt in range(3):
                    drv.execute_script("location.hash='/book/%s/%d.html'" % (bookid, cid))
                    time.sleep(1.0 if attempt < 2 else 2.5)
                    flush()
                    if cid in done:
                        break
                if cid not in done:
                    print("  仍缺失章节 %d，可稍后重跑本脚本自动续传。" % cid)
    finally:
        drv.quit()

    # 合并成 txt（含数据水印）
    outfile = os.path.join(outdir, title + ".txt")
    try:
        with open(outfile, "w", encoding="utf-8") as f:
            f.write("%s\n作者：%s\n" % (book["title"], book.get("author", "")))
            f.write("# 由 Book-Downloader 生成 —— %s\n\n" % WATERMARK)
            n_done = 0
            for cid in range(1, N + 1):
                p = os.path.join(tmpdir, "%06d.json" % cid)
                if os.path.exists(p):
                    with open(p, encoding="utf-8") as fj:
                        d = json.load(fj)
                    f.write("第 %d 章　%s\n\n" % (cid, d["t"]))
                    f.write(d["b"])
                    f.write("\n\n")
                    n_done += 1
            f.write("\n— 全文完 —\n%s\n" % WATERMARK)
        print("完成：%s" % outfile)
        return True
    except Exception as e:
        print("写入出错:", e)
        return False

# ---------- 主流程 ----------
def main():
    q = ask_query()
    if not q:
        print("已取消。")
        return
    items = search(q)
    book = pick(items)
    if not book:
        print("已取消。")
        return
    print("选择：《%s》 %s" % (book.get("title", ""), book.get("author", "")))
    print("保存到目录（直接回车 = 当前目录 %s）:" % os.getcwd(), end=" ", flush=True)
    try:
        p = input().strip()
    except EOFError:
        p = ""
    outdir = os.path.abspath(p if p else os.getcwd())
    if not os.path.isdir(outdir):
        print("目录不存在，将创建: %s" % outdir)
        os.makedirs(outdir, exist_ok=True)
    download_book(book, outdir)

if __name__ == "__main__":
    main()
PYEOF

python3 "$PYFILE" "$QUERY"