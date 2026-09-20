#!/usr/bin/env bash
# Gobi — cài / cập nhật / gỡ trên MÁY CHỦ RIÊNG của bạn.
#
# Dùng:
#   sudo ./cai-gobi.sh cai        # cài lần đầu (chạy lại nhiều lần cũng không sao)
#   sudo ./cai-gobi.sh capnhat    # lên bản mới, dữ liệu giữ nguyên
#   sudo ./cai-gobi.sh trangthai  # đang chạy không, bản nào
#   sudo ./cai-gobi.sh nhat-ky    # in nhật ký để gửi đi khi trục trặc
#   sudo ./cai-gobi.sh go         # gỡ sạch (XOÁ CẢ DỮ LIỆU)
#
# Một tệp duy nhất: `docker-compose.yml` và `Caddyfile` được tệp này ghi ra lúc cài, nên bạn
# chỉ phải tải về đúng một thứ.
#
# 🔴 Luật của tệp này, giữ giùm khi sửa:
#   · Mật khẩu, mã băm mật khẩu và mã truy cập ⛔ được in ra màn hình hay ghi vào nhật ký.
#   · Chạy lại bao nhiêu lần cũng ⛔ được hỏng thứ đã có.
#   · Mọi câu báo lỗi phải nói được CÁCH SỬA, bằng tiếng Việt người thường đọc hiểu.

set -euo pipefail

# ── Hằng số ─────────────────────────────────────────────────────────────────────────────────────
KHO_ANH_MAC_DINH="${GOBI_KHO_ANH:-ghcr.io/10x-os/gobi}"
MAY_CHU_KHO="${KHO_ANH_MAC_DINH%%/*}"   # lấy từ chính tên kho, ⛔ gõ lại ở hai chỗ rồi lệch nhau

# Bản sẽ cài nếu không ai nói gì khác. ⛔ đổi thành `latest`: `latest` trỏ đi đâu là chuyện của
# hôm đó, nên máy sẽ chạy một bản khác với bản người hỗ trợ đang cầm mà ⛔ ai biết. Bản cụ thể thì
# truyền `--ban <tên bản>`.
BAN_MAC_DINH="${GOBI_BAN:-on-dinh}"

THU_MUC="${GOBI_THU_MUC:-/opt/gobi}"
# ⚠️ Đặt ở ĐÂY, ⛔ đặt trong `lay_ma()`: hàm đó luôn được gọi trong `$( )`, tức là một tiến trình
# CON — mọi phép gán trong đó chết theo tiến trình con, và `luu_ma()` sau đó cầm một biến RỖNG.
TEP_MA="$THU_MUC/ma-truy-cap"

# Sàn cấu hình máy. 1.800 MB là đường phân đôi giữa gói «2 GB» (máy khai ~1.900–2.000 MB nên qua)
# và gói «1 GB» (khai ~950–1.000 MB nên trượt). Gói 1 GB chạy được lúc bình thường nhưng nghẹn
# đúng lúc Gobi xử lý một tài liệu dài — tức nghẹn đúng lúc người dùng cần nó nhất.
RAM_TOI_THIEU_MB=1800
DIA_TOI_THIEU_GB=10

CONG_TRONG=7391          # cổng của ứng dụng, chỉ sống trong mạng nội bộ của Docker

# ── In ra ───────────────────────────────────────────────────────────────────────────────────────
NHAT_KY=""

noi()  { printf '%s\n' "$*"; [ -n "$NHAT_KY" ] && printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"$NHAT_KY" || true; }
buoc() { printf '\n▶ %s\n' "$*"; [ -n "$NHAT_KY" ] && printf '[%s] ▶ %s\n' "$(date '+%F %T')" "$*" >>"$NHAT_KY" || true; }
ok()   { printf '  ✓ %s\n' "$*"; [ -n "$NHAT_KY" ] && printf '[%s]   OK %s\n' "$(date '+%F %T')" "$*" >>"$NHAT_KY" || true; }
canh() { printf '  ⚠ %s\n' "$*"; [ -n "$NHAT_KY" ] && printf '[%s]   CANH BAO %s\n' "$(date '+%F %T')" "$*" >>"$NHAT_KY" || true; }

loi() {
  printf '\n✗ %s\n' "$1" >&2
  shift || true
  [ $# -gt 0 ] && printf '\n  Cách sửa:\n' >&2 && printf '  · %s\n' "$@" >&2
  [ -n "$NHAT_KY" ] && printf '[%s] LOI %s\n' "$(date '+%F %T')" "$1" >>"$NHAT_KY" || true
  exit 1
}

# ── Tham số ─────────────────────────────────────────────────────────────────────────────────────
VIEC="${1:-giup}"; shift || true

TEN_MIEN=""; EMAIL=""; BAN=""; TOKEN_TEP=""; DOI_MAT_KHAU=0; THU_CUC_BO=0; ANH_TU_CHI_DINH=""
KHONG_LUU_MA=0

while [ $# -gt 0 ]; do
  case "$1" in
    --ten-mien)     TEN_MIEN="${2:-}"; shift 2 ;;
    --email)        EMAIL="${2:-}"; shift 2 ;;
    --ban)          BAN="${2:-}"; shift 2 ;;
    --tep-token)    TOKEN_TEP="${2:-}"; shift 2 ;;
    --doi-mat-khau) DOI_MAT_KHAU=1; shift ;;
    --khong-luu-ma) KHONG_LUU_MA=1; shift ;;
    --thu-cuc-bo)   THU_CUC_BO=1; shift ;;
    --anh)          ANH_TU_CHI_DINH="${2:-}"; shift 2 ;;
    -h|--help)      VIEC="giup"; shift ;;
    *) loi "Không hiểu tham số «$1»." "Chạy «./cai-gobi.sh» không kèm gì để xem hướng dẫn." ;;
  esac
done

BAN="${BAN:-$BAN_MAC_DINH}"

# ── Tiện ích ────────────────────────────────────────────────────────────────────────────────────
co_lenh() { command -v "$1" >/dev/null 2>&1; }

docker_compose() { docker compose --project-directory "$THU_MUC" "$@"; }

doc_env() {  # doc_env <TEN_BIEN> — đọc một biến trong .env, KHÔNG in ra
  [ -f "$THU_MUC/.env" ] || return 1
  sed -n "s/^$1=//p" "$THU_MUC/.env" | head -n1
}

# ── Mã truy cập phần mềm ────────────────────────────────────────────────────────────────────────
lay_ma() {  # in mã ra stdout cho hàm gọi hứng — ⛔ ghi log, ⛔ hiện màn hình
  if [ -n "$TOKEN_TEP" ]; then
    [ -r "$TOKEN_TEP" ] || loi "Không đọc được tệp mã truy cập «${TOKEN_TEP}»." \
        "Kiểm lại đường dẫn — gõ «ls ${TOKEN_TEP}» xem tệp có thật ở đó không."
    tr -d '\r\n' <"$TOKEN_TEP"
  elif [ -n "${GOBI_MA_TRUY_CAP:-}" ]; then
    printf '%s' "$GOBI_MA_TRUY_CAP" | tr -d '\r\n'
  elif [ -r "$TEP_MA" ]; then
    tr -d '\r\n' <"$TEP_MA"
  fi
}

luu_ma() {  # giữ mã lại để lần `capnhat` sau ⛔ phải dán mã lại
  [ -n "$TEP_MA" ] || loi "Lỗi bên trong lệnh cài (chưa biết cất mã ở đâu)." "Báo người phụ trách kèm câu này."
  [ "$KHONG_LUU_MA" -eq 1 ] && { rm -f "$TEP_MA"; return 0; }
  mkdir -p "$THU_MUC"
  ( umask 077; printf '%s' "$1" >"$TEP_MA" )
  chmod 600 "$TEP_MA"
}

kiem_mang_kho_anh() {
  # Tách «mạng hỏng» khỏi «mã sai» TRƯỚC khi đăng nhập. Thiếu bước này thì hai chuyện rất khác nhau
  # cùng hiện ra một câu, và người dùng đi sửa nhầm thứ.
  # ⚠️ ⛔ thêm `|| echo 000` ở đây: hỏng mạng thì curl ĐÃ in «000» rồi MỚI thoát khác 0, nên cái
  # `||` in thêm một lần nữa ⇒ chuỗi thành «000 000», khác «000», và phép kiểm này lọt — máy mất
  # mạng mà script đổ oan cho cái mã. Lấy 3 ký tự cuối cho chắc.
  [ -n "${GOBI_KHO_ANH:-}" ] && return 0
  local ma_http
  # `|| true` là bắt buộc: script bật `pipefail`, curl hỏng làm cả ống hỏng ⇒ phép gán hỏng ⇒
  # `set -e` giết script mà KHÔNG IN GÌ.
  ma_http=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 20 "https://${MAY_CHU_KHO}/v2/" 2>/dev/null \
            | tr -cd '0-9' | tail -c 3 || true)
  [ -n "$ma_http" ] && [ "$ma_http" != "000" ] && return 0
  loi "Máy chủ của bạn không ra được Internet, nên chưa tải Gobi về được — chưa liên quan gì tới cái mã." \
      "Thử xem mạng có thông không:  ping -c2 1.1.1.1" \
      "Thông rồi mà vẫn báo câu này thì nhà cung cấp máy chủ đang chặn — nhắn hỗ trợ của họ." \
      "Mạng ổn rồi thì chạy lại đúng lệnh vừa rồi, không mất gì cả."
}

# ── Kiểm máy ────────────────────────────────────────────────────────────────────────────────────
kiem_quyen() {
  [ "$(id -u)" -eq 0 ] && return 0
  docker info >/dev/null 2>&1 && return 0
  loi "Lệnh này cần quyền quản trị máy." \
      "Gõ lại có chữ «sudo» ở đầu:  sudo $0 $VIEC"
}

kiem_may() {
  buoc "Kiểm máy chủ"

  if [ "$(uname -s)" != "Linux" ]; then
    [ "$THU_CUC_BO" -eq 1 ] || loi "Máy này không phải Linux — Gobi chỉ cài được trên máy chủ Linux (Ubuntu)." \
        "Mua một máy chủ (VPS) chạy Ubuntu rồi chạy lại lệnh này TRÊN MÁY CHỦ đó, không phải trên máy tính cá nhân."
    canh "Không phải Linux — bỏ qua các phép đo dành cho máy chủ."
  fi

  if [ -r /proc/meminfo ]; then
    local ram; ram=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo)
    if [ "$ram" -lt "$RAM_TOI_THIEU_MB" ]; then
      loi "Máy chủ chỉ có ${ram} MB bộ nhớ, cần ít nhất ${RAM_TOI_THIEU_MB} MB." \
          "Nâng gói máy chủ lên mức có nhiều bộ nhớ hơn rồi chạy lại lệnh này."
    fi
    ok "Bộ nhớ: ${ram} MB"
  else
    canh "Không đọc được dung lượng bộ nhớ của máy — bỏ qua phép đo này."
  fi

  local dia; dia=$(df -Pk / | awk 'NR==2{print int($4/1048576)}')
  if [ "${dia:-0}" -lt "$DIA_TOI_THIEU_GB" ]; then
    loi "Ổ đĩa chỉ còn ${dia} GB trống, cần ít nhất ${DIA_TOI_THIEU_GB} GB." \
        "Xoá bớt tệp trên máy chủ, hoặc nâng gói máy chủ lên ổ lớn hơn."
  fi
  ok "Ổ đĩa còn trống: ${dia} GB"

  co_lenh docker || loi "Máy chủ chưa có Docker." \
      "Chọn lại máy chủ bằng mẫu «Ubuntu + Docker» của nhà cung cấp, HOẶC cài tay bằng lệnh:" \
      "curl -fsSL https://get.docker.com | sh"
  docker info >/dev/null 2>&1 || loi "Docker có cài nhưng chưa chạy." \
      "Bật nó lên:  sudo systemctl start docker"
  docker compose version >/dev/null 2>&1 || loi "Docker trên máy này thiếu phần «compose»." \
      "Cài lại Docker bản mới bằng lệnh:  curl -fsSL https://get.docker.com | sh"
  ok "Docker: $(docker version --format '{{.Server.Version}}' 2>/dev/null)"

  if co_lenh ss; then
    for cong in 80 443; do
      if ss -ltnH "sport = :$cong" 2>/dev/null | grep -q .; then
        if docker ps --format '{{.Names}}' | grep -qx 'gobi-cong-vao'; then
          ok "Cổng $cong đang do Gobi giữ (lần cài trước) — sẽ dùng lại."
        else
          loi "Cổng $cong trên máy chủ đang bị một phần mềm khác chiếm." \
              "Máy chủ này phải trống cổng 80 và 443 thì Gobi mới xin được chứng chỉ bảo mật." \
              "Dùng một máy chủ mới tinh, hoặc tắt phần mềm web đang chạy sẵn trên máy."
        fi
      fi
    done
    ok "Cổng 80 và 443 dùng được"
  fi
}

# ── Hỏi tên miền ────────────────────────────────────────────────────────────────────────────────
hoi_ten_mien() {
  buoc "Tên miền"

  local cu; cu=$(doc_env GOBI_TEN_MIEN 2>/dev/null || true)
  if [ -z "$TEN_MIEN" ] && [ -n "$cu" ]; then
    TEN_MIEN="$cu"
    ok "Dùng lại tên miền đã cài lần trước: $TEN_MIEN"
  fi

  while [ -z "$TEN_MIEN" ]; do
    printf '\n  Tên miền BẠN ĐÃ MUA và đã trỏ về máy chủ này (ví dụ: gobi.tencuaban.com)\n'
    printf '  — gõ đúng như trong hướng dẫn, không có https://, không có dấu / ở cuối\n'
    printf '  Tên miền: '
    read -r TEN_MIEN </dev/tty || loi "Không nhập được tên miền."
  done

  TEN_MIEN="${TEN_MIEN#http://}"; TEN_MIEN="${TEN_MIEN#https://}"; TEN_MIEN="${TEN_MIEN%%/*}"
  printf '%s' "$TEN_MIEN" | grep -Eq '^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$' \
    || loi "«${TEN_MIEN}» không giống một tên miền." "Gõ lại dạng: gobi.tencuaban.com"
  ok "Tên miền: $TEN_MIEN"

  if [ "$THU_CUC_BO" -eq 1 ]; then
    canh "Bỏ qua phép kiểm tên miền trỏ về máy này."
    return 0
  fi

  # 🔴 DỪNG CỨNG khi tên miền chưa trỏ đúng. Không phải để làm khó: chạy tiếp là cổng vào đi xin
  # chứng chỉ, xin hỏng vài lần liên tiếp thì nhà cấp chứng chỉ KHOÁ tên miền đó lại hàng giờ —
  # lúc trỏ đúng rồi vẫn không xin được.
  buoc "Kiểm tên miền đã trỏ về máy chủ này chưa"
  local ip_may ip_ten
  ip_may=$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null \
        || curl -fsS --max-time 10 https://ifconfig.me 2>/dev/null || true)
  ip_ten=$(getent ahostsv4 "$TEN_MIEN" 2>/dev/null | awk 'NR==1{print $1}' || true)

  if [ -z "$ip_may" ]; then
    loi "Máy chủ này chưa ra được Internet nên chưa kiểm được tên miền." \
        "Thử:  ping -c2 1.1.1.1" \
        "Mạng đã thông thì chạy lại lệnh cài."
  fi

  if [ -z "$ip_ten" ]; then
    loi "Tên miền «${TEN_MIEN}» chưa trỏ đi đâu cả — dừng lại ở đây." \
        "Vào trang quản lý tên miền, thêm một bản ghi loại A trỏ về địa chỉ: $ip_may" \
        "Khai xong CHỜ 15–30 phút (có khi tới vài giờ) cho tên miền lan ra khắp Internet." \
        "Tự kiểm bằng lệnh này, thấy đúng $ip_may thì chạy lại lệnh cài:  getent ahostsv4 $TEN_MIEN"
  fi

  if [ "$ip_may" != "$ip_ten" ]; then
    loi "Tên miền «${TEN_MIEN}» đang trỏ về $ip_ten, nhưng máy chủ này là $ip_may — dừng lại ở đây." \
        "Nếu bạn VỪA khai bản ghi xong: chờ thêm 15–30 phút rồi chạy lại, tên miền cần thời gian lan ra." \
        "Nếu đã chờ lâu rồi: vào trang quản lý tên miền, sửa bản ghi loại A của «${TEN_MIEN}» thành $ip_may." \
        "Tự kiểm bằng:  getent ahostsv4 $TEN_MIEN"
  fi
  ok "Tên miền đã trỏ đúng về máy chủ này ($ip_may)"
}

hoi_email() {
  buoc "Email"
  local cu; cu=$(doc_env GOBI_EMAIL 2>/dev/null || true)
  if [ -z "$EMAIL" ] && [ -n "$cu" ]; then EMAIL="$cu"; ok "Dùng lại email đã khai lần trước"; return 0; fi
  while [ -z "$EMAIL" ]; do
    printf '\n  Email của bạn — chỉ dùng để nhận thư nhắc khi chứng chỉ bảo mật sắp hết hạn.\n'
    printf '  Email: '
    read -r EMAIL </dev/tty || loi "Không nhập được email."
    printf '%s' "$EMAIL" | grep -Eq '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' || { canh "Email chưa đúng dạng, gõ lại."; EMAIL=""; }
  done
  ok "Email: $EMAIL"
}

# ── Kéo ảnh ─────────────────────────────────────────────────────────────────────────────────────
dang_nhap_kho_anh() {
  # Mỗi người một mã riêng: mã của bạn chỉ mở được kho phần mềm Gobi, và huỷ được riêng mà ⛔ ảnh
  # hưởng ai khác.
  #
  # 🔴 Ba luật của mã trong script này, giữ giùm khi sửa:
  #   ① ⛔ nhúng cứng bất cứ mã nào vào mã nguồn.
  #   ② ⛔ in mã ra màn hình, ⛔ ghi vào nhật ký, ⛔ nhận qua tham số dòng lệnh trần — dòng lệnh hiện
  #      trong `ps` của mọi người dùng trên máy. Chỉ nhận qua BIẾN MÔI TRƯỜNG hoặc TỆP.
  #   ③ Mã chỉ nằm ĐÚNG MỘT CHỖ trên đĩa: `$THU_MUC/ma-truy-cap`, chmod 600, và lệnh `go` xoá nó.
  #      Kéo xong là ĐĂNG XUẤT khỏi kho ⇒ mã ⛔ nằm lại trong cấu hình của Docker, nơi nó sẽ bị
  #      kéo theo mỗi lần ai đó sao lưu hay chép thư mục của root đi nơi khác.
  if [ -n "$ANH_TU_CHI_DINH" ]; then
    canh "Đang dùng bản cài chỉ định sẵn: $ANH_TU_CHI_DINH"
    return 0
  fi

  buoc "Mã truy cập phần mềm"

  local ma; ma=$(lay_ma)

  # ── Ba trường hợp, ba câu khác hẳn nhau ── ① THIẾU MÃ ─────────────────────────────────────────
  if [ -z "$ma" ]; then
    loi "Chưa có mã truy cập phần mềm — chưa tải Gobi về được." \
        "Mã là một dãy ký tự người phụ trách gửi RIÊNG cho bạn (mỗi người một mã khác nhau)." \
        "Lưu mã vào một tệp rồi chạy:  sudo $0 $VIEC --tep-token /root/ma-gobi.txt" \
        "Chưa ai gửi mã thì nhắn xin — đừng mượn mã của người khác, mã của họ không mở cho bạn."
  fi

  kiem_mang_kho_anh   # ③ MẠNG HỎNG — tách ra TRƯỚC, để ⛔ đổ oan cho cái mã

  local bao_loi nguoi="${GOBI_NGUOI_DUNG_KHO:-gobi-hoc-vien}"
  if bao_loi=$(printf '%s' "$ma" | docker login "$MAY_CHU_KHO" -u "$nguoi" --password-stdin 2>&1 >/dev/null); then
    ok "Mã truy cập dùng được"
    luu_ma "$ma"
    return 0
  fi

  # ⚠️ ⛔ ĐƯA `$bao_loi` RA MÀN HÌNH: đó là câu tiếng Anh của công cụ, người dùng ⛔ hiểu, và có trường
  # hợp nó chép lại một phần thứ vừa gửi đi. Chỉ ĐỌC nó để đoán đúng loại lỗi rồi nói bằng lời mình.
  case "$bao_loi" in
    # ── ② MÃ SAI HOẶC ĐÃ BỊ HUỶ ────────────────────────────────────────────────────────────────
    *[Uu]nauthorized*|*401*|*"incorrect username or password"*|*denied*|*[Ff]orbidden*|*403*)
      loi "Mã truy cập không dùng được — chuyện của cái mã thôi, máy chủ của bạn vẫn tốt." \
          "① Nhiều khả năng nhất là dán thiếu hoặc thừa ký tự: mở lại tin nhắn, chép TOÀN BỘ dãy mã, không thừa dấu cách, không thừa dòng trống." \
          "② Nếu chép đúng rồi mà vẫn báo câu này thì mã của bạn đã bị huỷ hoặc hết hạn — nhắn người phụ trách cấp mã mới." \
          "Có mã mới thì chạy lại:  sudo $0 $VIEC --tep-token /root/ma-gobi.txt" ;;
    *)
      loi "Chưa vào được kho phần mềm, mà không phải vì mã sai." \
          "Thường là mạng của máy chủ chập chờn hoặc kho đang bận — chờ 5 phút rồi chạy lại đúng lệnh vừa rồi, không mất gì cả." \
          "Ba lần vẫn vậy thì nhắn người phụ trách: «vào kho không được, mã thì chưa bị báo sai»." ;;
  esac
}

dang_xuat_kho_anh() {
  # Kéo xong là đăng xuất. Mã nằm trong cấu hình của Docker là nằm dạng chữ thường, và bị kéo theo
  # mỗi lần ai đó sao lưu hay chép thư mục của root đi nơi khác. Bản của mình vẫn giữ ở `$TEP_MA`
  # để lần `capnhat` sau ⛔ phải dán lại mã.
  [ -n "$ANH_TU_CHI_DINH" ] && return 0
  docker logout "$MAY_CHU_KHO" >/dev/null 2>&1 || true
}

keo_anh() {
  buoc "Tải Gobi về máy chủ (khoảng 1 GB, vài phút tuỳ đường mạng — đừng đóng cửa sổ)"
  ANH="${ANH_TU_CHI_DINH:-${KHO_ANH_MAC_DINH}:${BAN}}"
  if [ -n "$ANH_TU_CHI_DINH" ]; then
    docker image inspect "$ANH" >/dev/null 2>&1 \
      || loi "Không thấy bản cài «${ANH}» trên máy này." "Bỏ tham số «--anh» đi để tải bản cài về từ kho."
    ok "Đã có Gobi bản «${BAN}» trên máy"
    return 0
  fi

  local bao_loi
  if bao_loi=$(docker pull "$ANH" 2>&1 >/dev/null); then
    dang_xuat_kho_anh
    ok "Đã tải xong Gobi bản «${BAN}»"
    return 0
  fi
  dang_xuat_kho_anh

  # Lỗi lúc KÉO, khác lỗi lúc đăng nhập: mã đúng nhưng ⛔ mở cho đúng bản này, hoặc bản ⛔ tồn tại.
  case "$bao_loi" in
    *"not found"*|*"manifest unknown"*|*"not exist"*)
      loi "Kho không có bản tên «${BAN}»." \
          "Hỏi người phụ trách tên bản đúng, rồi chạy lại kèm:  --ban <tên bản người phụ trách đưa>" ;;
    *[Uu]nauthorized*|*401*|*denied*|*[Ff]orbidden*|*403*)
      loi "Mã của bạn vào được kho nhưng không mở được bản cài — nhiều khả năng mã vừa bị huỷ hoặc cấp thiếu quyền." \
          "Nhắn người phụ trách: «mã đăng nhập được nhưng không tải được bản cài»." \
          "Có mã mới thì chạy lại:  sudo $0 $VIEC --tep-token /root/ma-gobi.txt" ;;
    *)
      loi "Tải Gobi về không xong." \
          "Thường là mạng đứt giữa chừng — chạy lại đúng lệnh vừa rồi, phần đã tải xong không phải tải lại." \
          "Kiểm mạng máy chủ:  ping -c2 1.1.1.1" ;;
  esac
}

# ── Mật khẩu ────────────────────────────────────────────────────────────────────────────────────
sinh_ma_bam() {
  # Mật khẩu KHÔNG hiện lên màn hình, KHÔNG vào nhật ký, KHÔNG vào dòng lệnh.
  # Mã băm đi thẳng từ đầu ra của container vào biến rồi vào `.env` (chmod 600) — không in ra.
  buoc "Mật khẩu đăng nhập"

  local cu; cu=$(doc_env GOBI_PASSWORD_HASH 2>/dev/null || true)
  if [ -n "$cu" ] && [ "$DOI_MAT_KHAU" -eq 0 ]; then
    ok "Giữ nguyên mật khẩu đã đặt lần trước (muốn đổi thì thêm:  --doi-mat-khau)"
    MA_BAM="$cu"
    return 0
  fi

  local mk mk2 tty_cu=""
  # Tắt hiện chữ cho CẢ hai lần gõ. `read -rs` bật lại chế độ hiện chữ ngay sau lần gõ thứ nhất,
  # mà người dán mật khẩu (thay vì gõ) thì cả hai dòng vào cùng lúc ⇒ dòng thứ hai HIỆN LÊN màn
  # hình. Khoá echo suốt cả đoạn này thì không còn khe đó.
  if tty_cu=$(stty -g </dev/tty 2>/dev/null); then
    stty -echo </dev/tty 2>/dev/null || true
    trap 'stty "$tty_cu" </dev/tty 2>/dev/null || true' EXIT INT TERM
  fi
  while :; do
    printf '\n  Đặt mật khẩu để đăng nhập Gobi (ít nhất 12 ký tự).\n'
    printf '  Gõ xong bấm Enter — màn hình sẽ KHÔNG hiện chữ, đó là bình thường.\n'
    printf '  Mật khẩu: '
    read -rs mk </dev/tty; printf '\n'
    printf '  Gõ lại:   '
    read -rs mk2 </dev/tty; printf '\n'
    [ "$mk" = "$mk2" ] || { canh "Hai lần gõ khác nhau, làm lại."; continue; }
    [ "${#mk}" -ge 12 ] || { canh "Ngắn quá — Gobi của bạn nằm trên Internet, mật khẩu phải từ 12 ký tự trở lên."; continue; }
    break
  done
  if [ -n "$tty_cu" ]; then stty "$tty_cu" </dev/tty 2>/dev/null || true; trap - EXIT INT TERM; fi

  MA_BAM=$(printf '%s' "$mk" | docker run --rm -i --entrypoint python "$ANH" -c \
    'import sys; from gobi.auth import hash_password; sys.stdout.write(hash_password(sys.stdin.read()))' 2>/dev/null) \
    || loi "Không tạo được mật khẩu." "Chạy lại lệnh cài một lần nữa."
  unset mk mk2
  [ -n "$MA_BAM" ] || loi "Không tạo được mật khẩu." "Chạy lại lệnh cài một lần nữa."
  case "$MA_BAM" in *'$'*) loi "Mật khẩu tạo ra có ký tự không dùng được." "Đặt lại mật khẩu khác." ;; esac
  ok "Đã đặt mật khẩu (không hiện ra ở đâu cả — nhớ kỹ nhé)"
}

# ── Ghi tệp cấu hình ────────────────────────────────────────────────────────────────────────────
ghi_compose() {
cat >"$THU_MUC/docker-compose.yml" <<'HET_COMPOSE'
# Gobi — bản chạy trên máy chủ riêng của bạn.
# ⛔ Sửa tay tệp này. Nó được lệnh cài ghi lại mỗi lần chạy, sửa gì cũng mất.
#
# Hai container:
#   gobi          — ứng dụng. ⛔ mở cổng ra ngoài, chỉ nói chuyện với cổng vào qua mạng nội bộ.
#   gobi-cong-vao — giữ cổng 80/443, tự xin và tự gia hạn chứng chỉ bảo mật (HTTPS).

name: gobi

services:
  gobi:
    image: ${GOBI_ANH:?Thiếu GOBI_ANH trong .env — chạy lại lệnh cài}
    container_name: gobi
    restart: unless-stopped
    # Trần bộ nhớ của ứng dụng. Lúc nặng nhất nó ăn quãng một phần tư chỗ này, nên trần đang rộng
    # rãi có chủ đích — ⛔ hạ xuống sát mức đo được rồi để container bị giết lúc gặp tài liệu dài.
    mem_limit: 768m
    cpus: 1.0
    # Ứng dụng là tiến trình số 1 trong container — cho nó đủ thời gian đóng dữ liệu khi tắt.
    stop_grace_period: 20s
    expose:
      - "7391"
    environment:
      # Bắt buộc. Thiếu là cổng đăng nhập đóng (503) — cấu hình hỏng ⛔ được là cửa mở.
      - GOBI_PASSWORD_HASH=${GOBI_PASSWORD_HASH:?Thiếu mật khẩu trong .env — chạy lại lệnh cài}
      - GIT_SHA=${GOBI_BAN:-}
      # Khoá của nhà cung cấp AI: để trống thì bạn tự dán khoá trong phần Cài đặt của app.
      - OPENROUTER_API_KEY=${OPENROUTER_API_KEY:-}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
      - OPENAI_API_KEY=${OPENAI_API_KEY:-}
      - GOBI_MODEL=${GOBI_MODEL:-}
      - GOBI_MODEL_PROVIDER=${GOBI_MODEL_PROVIDER:-}
      # Nút «Báo lỗi»: để trống thì nút vẫn hiện nhưng báo «chưa nối trạm báo lỗi».
      - GOBI_INTAKE_URL=${GOBI_INTAKE_URL:-}
      - GOBI_INTAKE_TOKEN=${GOBI_INTAKE_TOKEN:-}
      # ⛔ Thêm API_SERVER_KEY vào đây: có biến đó là mọi lượt trò chuyện bị từ chối.
      # GOBI_HOSTED=1 đã nằm sẵn trong ảnh — ⛔ đặt lại ở đây.
    volumes:
      - gobi-du-lieu:/data    # 🔴 MẤT VOLUME NÀY LÀ MẤT TOÀN BỘ KHO CỦA BẠN
    networks:
      - gobi-mang

  gobi-cong-vao:
    image: caddy:2.10-alpine
    container_name: gobi-cong-vao
    restart: unless-stopped
    mem_limit: 128m
    ports:
      - "80:80"
      - "443:443"
    environment:
      - GOBI_TEN_MIEN=${GOBI_TEN_MIEN:?Thiếu tên miền trong .env — chạy lại lệnh cài}
      - GOBI_EMAIL=${GOBI_EMAIL:?Thiếu email trong .env — chạy lại lệnh cài}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - gobi-chung-chi:/data      # chứng chỉ bảo mật — mất thì phải xin lại từ đầu
      - gobi-cong-vao-cau-hinh:/config
    depends_on:
      - gobi
    networks:
      - gobi-mang

volumes:
  gobi-du-lieu:
  gobi-chung-chi:
  gobi-cong-vao-cau-hinh:

networks:
  gobi-mang:
HET_COMPOSE
}

ghi_caddyfile() {
cat >"$THU_MUC/Caddyfile" <<'HET_CADDY'
# Cổng vào của Gobi — giữ cổng 80/443, tự xin chứng chỉ HTTPS, chuyển tiếp vào ứng dụng.
# ⛔ Sửa tay: lệnh cài ghi lại tệp này mỗi lần chạy.
{
	email {$GOBI_EMAIL}
}

{$GOBI_TEN_MIEN} {
	encode zstd gzip
	# Giữ nguyên tên miền gốc khi chuyển tiếp — ứng dụng đối chiếu tên miền để chống giả mạo biểu mẫu.
	reverse_proxy gobi:7391
}
HET_CADDY
}

ghi_env() {
  local cu_or=""; local cu_an=""; local cu_op=""; local cu_mo=""; local cu_ncc=""; local cu_iu=""; local cu_it=""
  cu_or=$(doc_env OPENROUTER_API_KEY 2>/dev/null || true)
  cu_an=$(doc_env ANTHROPIC_API_KEY 2>/dev/null || true)
  cu_op=$(doc_env OPENAI_API_KEY 2>/dev/null || true)
  cu_mo=$(doc_env GOBI_MODEL 2>/dev/null || true)
  cu_ncc=$(doc_env GOBI_MODEL_PROVIDER 2>/dev/null || true)
  cu_iu=$(doc_env GOBI_INTAKE_URL 2>/dev/null || true)
  cu_it=$(doc_env GOBI_INTAKE_TOKEN 2>/dev/null || true)

  ( umask 077
    cat >"$THU_MUC/.env" <<HET_ENV
# Gobi — cấu hình máy chủ của bạn. 🔴 TỆP NÀY CHỨA MẬT KHẨU ĐÃ MÃ HOÁ, ⛔ gửi cho ai.
# Lệnh cài ghi lại tệp này mỗi lần chạy; mấy dòng khoá AI bên dưới thì được giữ nguyên.
GOBI_ANH=$ANH
GOBI_BAN=$BAN
GOBI_TEN_MIEN=$TEN_MIEN
GOBI_EMAIL=$EMAIL
GOBI_PASSWORD_HASH=$MA_BAM
OPENROUTER_API_KEY=$cu_or
ANTHROPIC_API_KEY=$cu_an
OPENAI_API_KEY=$cu_op
GOBI_MODEL=$cu_mo
GOBI_MODEL_PROVIDER=$cu_ncc
GOBI_INTAKE_URL=$cu_iu
GOBI_INTAKE_TOKEN=$cu_it
HET_ENV
  )
  chmod 600 "$THU_MUC/.env"
}

# ── Chạy + tự kiểm ──────────────────────────────────────────────────────────────────────────────
kiem_anh_dung() {
  # Cổng đăng nhập chỉ bật khi ảnh có sẵn GOBI_HOSTED=1. Ảnh sai là Gobi chạy KHÔNG có mật khẩu.
  docker image inspect "$ANH" --format '{{json .Config.Env}}' 2>/dev/null | grep -q '"GOBI_HOSTED=1"' \
    || loi "Bản Gobi tải về không phải bản dành cho máy chủ — dừng lại cho an toàn (chạy tiếp là Gobi của bạn mở toang, không hỏi mật khẩu)." \
           "Hỏi người phụ trách tên bản đúng, rồi chạy lại kèm:  --ban <tên bản>"
}

cho_khoe() {
  buoc "Chờ Gobi khởi động rồi tự kiểm"
  local i
  for i in $(seq 1 60); do
    if docker exec gobi python -c \
      "import sys,urllib.request,json; d=json.load(urllib.request.urlopen('http://127.0.0.1:${CONG_TRONG}/health',timeout=4)); sys.exit(0 if d.get('ok') else 1)" \
      >/dev/null 2>&1; then
      ok "Gobi đã chạy và tự báo khoẻ (lần thử thứ $i)"
      return 0
    fi
    sleep 2
  done
  loi "Gobi khởi động nhưng chưa báo khoẻ sau 2 phút." \
      "Xem chuyện gì đang xảy ra:  sudo $0 nhat-ky" \
      "Gửi nguyên phần in ra đó cho người phụ trách."
}

kiem_ngoai_doi() {
  buoc "Kiểm đường vào từ Internet"
  local i ma
  for i in $(seq 1 45); do
    ma=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 8 "https://${TEN_MIEN}/health" 2>/dev/null || true)
    [ "$ma" = "200" ] && { ok "https://${TEN_MIEN} đã mở được"; return 0; }
    sleep 4
  done
  canh "Chưa vào được https://${TEN_MIEN} từ bên ngoài (mã trả về: ${ma:-không có})."
  printf '  Gobi VẪN đang chạy trên máy — thường là do tên miền chưa kịp trỏ về đây, hoặc chứng chỉ bảo mật đang xin dở.\n'
  printf '  Chờ 10 phút rồi mở lại. Vẫn không được thì gửi cho người phụ trách kết quả của lệnh:\n'
  printf '    sudo %s nhat-ky\n' "$0"
}

# ── Các việc ────────────────────────────────────────────────────────────────────────────────────
viec_cai() {
  kiem_quyen
  mkdir -p "$THU_MUC"
  NHAT_KY="$THU_MUC/nhat-ky-cai-dat.log"
  : >>"$NHAT_KY"; chmod 600 "$NHAT_KY"

  printf '\n═══ Cài Gobi lên máy chủ của bạn ═══\n'
  kiem_may
  hoi_ten_mien
  hoi_email
  dang_nhap_kho_anh
  keo_anh
  kiem_anh_dung
  sinh_ma_bam
  buoc "Ghi cấu hình vào $THU_MUC"
  ghi_compose; ghi_caddyfile; ghi_env
  ok "Đã ghi xong"

  buoc "Khởi động Gobi"
  docker_compose up -d --remove-orphans >/dev/null 2>&1 \
    || loi "Không khởi động được Gobi." "Xem lỗi chi tiết:  cd $THU_MUC && sudo docker compose up -d"
  ok "Đã khởi động"

  cho_khoe
  [ "$THU_CUC_BO" -eq 1 ] || kiem_ngoai_doi

  cat <<HET_XONG

═══════════════════════════════════════════════════════════
  ✓ XONG. Gobi của bạn đang chạy.

  Mở trình duyệt vào:   https://${TEN_MIEN}
  Đăng nhập bằng mật khẩu bạn vừa đặt.

  Ba việc nên làm tiếp:
  1. Mở địa chỉ trên, đăng nhập, đổi sang trang Cài đặt và dán khoá AI của bạn.
  2. Lưu mật khẩu vào chỗ nào an toàn — không ai lấy lại hộ bạn được.
  3. Ghi lại lệnh này để lần sau lên bản mới:
        sudo $0 capnhat

  Xem Gobi có đang chạy không:   sudo $0 trangthai
═══════════════════════════════════════════════════════════
HET_XONG
}

viec_capnhat() {
  kiem_quyen
  [ -f "$THU_MUC/.env" ] || loi "Chưa thấy Gobi được cài trên máy này." "Cài trước đã:  sudo $0 cai"
  NHAT_KY="$THU_MUC/nhat-ky-cai-dat.log"

  TEN_MIEN=$(doc_env GOBI_TEN_MIEN); EMAIL=$(doc_env GOBI_EMAIL); MA_BAM=$(doc_env GOBI_PASSWORD_HASH)
  [ -n "${MA_BAM:-}" ] || loi "Cấu hình cũ thiếu mật khẩu." "Chạy lại:  sudo $0 cai"

  printf '\n═══ Cập nhật Gobi ═══\n'
  buoc "Bản đang chạy"
  local truoc; truoc=$(docker exec gobi python -c \
    "import urllib.request,json; print(json.load(urllib.request.urlopen('http://127.0.0.1:${CONG_TRONG}/health',timeout=4)).get('version','?'))" 2>/dev/null || echo "không rõ")
  ok "Đang chạy bản: $truoc"

  dang_nhap_kho_anh
  keo_anh
  kiem_anh_dung

  buoc "Đổi sang bản mới (dữ liệu giữ nguyên — Gobi tự sao lưu trước khi đổi bản)"
  ghi_compose; ghi_caddyfile; ghi_env
  docker_compose up -d --remove-orphans >/dev/null 2>&1 \
    || loi "Không đổi sang bản mới được." "Xem lỗi chi tiết:  cd $THU_MUC && sudo docker compose up -d"
  cho_khoe

  local sau; sau=$(docker exec gobi python -c \
    "import urllib.request,json; print(json.load(urllib.request.urlopen('http://127.0.0.1:${CONG_TRONG}/health',timeout=4)).get('version','?'))" 2>/dev/null || echo "không rõ")
  cat <<HET_CN

═══════════════════════════════════════════════════════════
  ✓ Đã cập nhật.   $truoc  →  $sau
  Mở lại:  https://${TEN_MIEN}
═══════════════════════════════════════════════════════════
HET_CN
}

viec_trangthai() {
  [ -f "$THU_MUC/.env" ] || loi "Chưa thấy Gobi được cài trên máy này." "Cài trước đã:  sudo $0 cai"
  TEN_MIEN=$(doc_env GOBI_TEN_MIEN)
  printf '\n═══ Trạng thái Gobi ═══\n\n'
  docker_compose ps || true
  printf '\n'
  if docker exec gobi python -c \
    "import sys,urllib.request,json; d=json.load(urllib.request.urlopen('http://127.0.0.1:${CONG_TRONG}/health',timeout=4)); print('  ✓ Gobi khoẻ · bản', d.get('version','?'), '· dữ liệu', d.get('db','?')); sys.exit(0 if d.get('ok') else 1)" 2>/dev/null; then
    printf '  ✓ Địa chỉ: https://%s\n\n' "$TEN_MIEN"
  else
    printf '  ✗ Gobi không trả lời.\n    Xem chuyện gì xảy ra:  sudo %s nhat-ky\n\n' "$0"
    exit 1
  fi
}

viec_go() {
  kiem_quyen
  [ -d "$THU_MUC" ] || loi "Chưa thấy Gobi được cài trên máy này." "Không có gì để gỡ."
  cat <<'HET_CANH'

🔴 GỠ GOBI — ĐỌC KỸ TRƯỚC KHI GÕ

  Lệnh này xoá SẠCH: ứng dụng, cấu hình, VÀ TOÀN BỘ KHO TÀI LIỆU của bạn trên máy này.
  Không có nút hoàn tác. Không ai khôi phục lại hộ được.

  TRƯỚC KHI GỠ: mở Gobi, vào phần Cài đặt, bấm «Tải kho về» và kiểm tệp .zip đã nằm
  trên máy tính của bạn. Chưa có tệp đó thì đóng cửa sổ này lại, đừng gõ gì cả.

HET_CANH
  printf '  Chắc chắn xoá? Gõ đúng chữ in hoa  XOA  rồi Enter: '
  local tl; read -r tl </dev/tty || tl=""
  [ "$tl" = "XOA" ] || { printf '\n  Đã huỷ, không xoá gì cả.\n\n'; exit 0; }

  printf '\n  Đang gỡ...\n'
  docker_compose down -v --remove-orphans >/dev/null 2>&1 || true
  docker rm -f gobi gobi-cong-vao >/dev/null 2>&1 || true
  rm -f "$THU_MUC/ma-truy-cap"        # mã truy cập ⛔ được ở lại sau khi gỡ
  rm -rf "$THU_MUC"
  docker logout "$MAY_CHU_KHO" >/dev/null 2>&1 || true
  printf '\n  ✓ Đã gỡ sạch Gobi khỏi máy chủ này.\n\n'
}

viec_nhat_ky() {
  # Gom nhật ký của cả hai container vào một lệnh, để người gặp trục trặc ⛔ phải nhớ tên container
  # nào cũng ⛔ phải gõ hai lệnh. In NGUYÊN VĂN, ⛔ lọc chữ nào: lọc là tự bịt mắt mình trước đúng
  # thứ cần nhìn, và dòng bẩn thì phải sửa ở chỗ sinh ra nó chứ ⛔ phải giấu ở đây.
  [ -d "$THU_MUC" ] || loi "Chưa thấy Gobi được cài trên máy này." "Cài trước đã:  sudo $0 cai"
  printf '\n─── Nhật ký ứng dụng (50 dòng cuối) ───\n'
  docker logs --tail 50 gobi 2>&1 || printf '  (không đọc được — Gobi chưa chạy)\n'
  printf '\n─── Nhật ký cổng vào (30 dòng cuối) ───\n'
  docker logs --tail 30 gobi-cong-vao 2>&1 || printf '  (không đọc được — cổng vào chưa chạy)\n'
  printf '\n  Gửi toàn bộ phần trên cho người phụ trách.\n\n'
}

viec_giup() {
  cat <<HET_GIUP

Gobi — bộ não thứ hai chạy trên máy chủ riêng của bạn

  sudo $0 cai         Cài lần đầu. Chạy lại nhiều lần cũng không hỏng gì.
  sudo $0 capnhat     Lên bản mới nhất, dữ liệu giữ nguyên.
  sudo $0 trangthai   Xem Gobi có đang chạy không, bản nào.
  sudo $0 nhat-ky     In nhật ký để gửi cho người phụ trách khi có trục trặc.
  sudo $0 go          Gỡ sạch khỏi máy chủ (XOÁ CẢ DỮ LIỆU).

Tham số thêm cho lệnh «cai»:
  --ten-mien <tên>        Khai luôn tên miền, khỏi phải gõ khi được hỏi.
  --email <email>         Khai luôn email.
  --tep-token <đường dẫn> Tệp chứa mã truy cập kho phần mềm.
  --doi-mat-khau          Đặt lại mật khẩu đăng nhập.
  --ban <tên bản>         Cài một bản cụ thể thay vì bản mặc định.
  --khong-luu-ma          Không giữ mã truy cập lại trên máy chủ. Đổi lại: mỗi lần cập nhật sau
                          này phải đưa mã lại bằng --tep-token.

Mã truy cập cũng truyền được qua biến môi trường GOBI_MA_TRUY_CAP.

HET_GIUP
}

case "$VIEC" in
  cai)       viec_cai ;;
  trich)     mkdir -p "$THU_MUC"; ghi_compose; ghi_caddyfile ;;
  capnhat)   viec_capnhat ;;
  trangthai) viec_trangthai ;;
  nhat-ky)   viec_nhat_ky ;;
  go)        viec_go ;;
  giup|"")   viec_giup ;;
  *) loi "Không hiểu lệnh «${VIEC}»." "Chạy «$0» không kèm gì để xem danh sách lệnh." ;;
esac
