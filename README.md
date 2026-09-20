# Cài Gobi lên máy chủ của bạn

Kho này chứa đúng một thứ: **lệnh cài Gobi**.

Bạn không cần tải cả kho về. Trên máy chủ của bạn, chạy:

```bash
curl -fsSL https://raw.githubusercontent.com/10x-os/gobi-cai-dat/main/cai-gobi.sh -o cai-gobi.sh
chmod +x cai-gobi.sh
sudo ./cai-gobi.sh cai
```

Lệnh sẽ hỏi bạn tên miền và mật khẩu, rồi tự lo phần còn lại.

## Bạn cần có sẵn ba thứ

| | |
|---|---|
| **Một máy chủ** | chạy Ubuntu, có sẵn Docker, ít nhất 2 GB bộ nhớ |
| **Một tên miền** | đã trỏ về máy chủ đó |
| **Mã truy cập phần mềm** | người phụ trách gửi riêng cho bạn |

Chưa có đủ ba thứ trên thì đọc bản hướng dẫn từng bước có ảnh chụp mà người phụ trách gửi kèm — đừng chạy lệnh vội.

## Các lệnh khác

```bash
sudo ./cai-gobi.sh trangthai   # Gobi có đang chạy không, bản nào
sudo ./cai-gobi.sh capnhat     # lên bản mới, dữ liệu giữ nguyên
sudo ./cai-gobi.sh nhat-ky     # in nhật ký để gửi đi khi trục trặc
sudo ./cai-gobi.sh go          # gỡ sạch khỏi máy chủ (xoá cả dữ liệu)
```

## Gặp trục trặc

Chạy `sudo ./cai-gobi.sh nhat-ky` rồi gửi toàn bộ phần in ra cho người phụ trách.
