# 媒体信息查看 · vinfo

平台：macOS 自带 Bash；媒体属性由 mediainfo 提供。安装：brew install mediainfo。

用法：
  vinfo [目录]
  vinfo -t [目录]
  ./hub run media-info --recursive [目录] （普通 CLI）

默认扫描当前目录；-t 或 --recursive 递归子目录。只读，不修改媒体。显示完整路径、字节大小、格式、时长、分辨率、帧率、码率、声道与采样率。字段和单位由 MediaInfo 提供，缺失字段不显示。

支持 MOV/MP4/AVI/MKV/FLV/WMV/MPEG/MPG/M4V/3GP/WEBM，以及 MP3/WAV/FLAC/AAC/OGG/M4A/WMA，扩展名不区分大小写。不跟随子目录符号链接，不读取符号链接媒体文件。

示例：
  vinfo "$HOME/Movies"
  vinfo -t "/Volumes/Data/我的视频"

快捷命令 vinfo 进入 fzf 文件列表，选中项按需解析并缓存；刷新会清除缓存。
直接输入文字搜索，Enter 查看完整属性，Ctrl+R 刷新，Ctrl+O 切换目录，Ctrl+T 切换递归。
Alt+j/k 滚动预览，Ctrl+F/B 翻页，Esc 返回。无媒体时仍可切换目录或递归。
命令行路径含空格时用引号包裹；TUI 输入框直接填写路径。非交互环境使用 hub run media-info。

退出码：0 全部成功或无媒体；1 媒体读取/解析或扫描失败；2 参数/目录无效或依赖缺失；130 用户中断；143 收到终止信号。

实现使用 MediaInfo raw 固定标识配合 awk，不依赖翻译后的字段名，也不需要额外的语言运行环境。文件路径以原始参数传给 mediainfo，文件名中的引号和 shell 符号不会成为命令。
