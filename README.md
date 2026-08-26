# ORBI Smart Glasses Community Reimplementation

面向 ORBI 360 智能眼镜的社区改造项目。这个仓库保存我们编写的 iOS 端重实现、设备通信协议分析、原始媒体格式研究、NFS 媒体传输和 360 媒体处理代码。

> 项目仍在开发中。请先用测试设备验证网络控制、媒体下载和拼接结果，不要直接用于固件升级或重要素材处理。

## 项目内容

- SwiftUI iOS 应用：拍摄、实时预览、媒体浏览、设置和设备状态页面
- ORBI TCP 控制协议：连接 `192.168.2.1:8080`，使用 JSON 命令和 `\r\n\r\n` 分隔符
- NFSv3 媒体读取：从眼镜的 `nfs://192.168.2.1/run/RTOS/DCIM/...` 路径读取媒体
- `.CFG` 原始媒体包解析：识别媒体 UUID、相机源、标定参数、IMU 路径和相机顺序
- iOS 原生媒体处理：缩略图、原始照片拼接、视频拼接和降级预览输出
- 简单设备探测工具：不需要 BlueStacks 或 ADB，直接查看眼镜返回的状态参数

## 目录结构

```text
Orbi360iOS/
  Orbi360iOS.xcodeproj/       Xcode 工程
  Orbi360iOS/                 SwiftUI 应用源码
  Orbi360iOSTests/            单元测试
  tools/                      网络检查和设备探测工具
  docs/                       APK 分析和原始格式研究笔记
docs/                         项目级研究文档
preview/                      协议/界面预览页面
```

## 开始使用

### iOS 应用

需要 macOS、Xcode 和一台可连接 ORBI 眼镜热点的 iPhone 或测试环境。

```sh
open Orbi360iOS/Orbi360iOS.xcodeproj
```

在 Xcode 中选择 `Orbi360iOS` scheme 后运行。真实设备通信前，请让电脑或 iPhone 连接眼镜 Wi-Fi；眼镜控制服务默认地址为 `192.168.2.1:8080`。

### 设备状态探测

电脑连接眼镜 Wi-Fi 后，可以直接运行：

```sh
python3 Orbi360iOS/tools/orbi_probe.py
```

Windows 用户可以双击 `Orbi360iOS/tools/orbi_probe_windows.bat`。工具会请求 `get_info`、`get-status` 和 `get-settings`，并把眼镜返回的 JSON 参数打印出来。需要查看媒体列表时：

```sh
python3 Orbi360iOS/tools/orbi_probe.py --media
```

如果连接超时，先确认眼镜已启动 Wi-Fi 控制服务，并检查电脑是否连接了眼镜热点，而不是普通路由器网络。

## 已恢复的协议信息

| 项目 | 值 |
| --- | --- |
| 设备地址 | `192.168.2.1` |
| 控制端口 | `8080` |
| 实时流端口 | `5000`, `5002`, `5004`, `5006` |
| 命令格式 | `{"id": 1, "cmd": "get_info"}` |
| 消息分隔符 | `CRLF CRLF` (`\\r\\n\\r\\n`) |

已映射的命令包括 `get_info`、`get-status`、`get-settings`、`get_media_list`、`mode`、`start`、`stop`、`save`、`set-wifi` 和 `format-sd`。涉及写入设备、格式化 SD 卡或固件更新的功能请谨慎使用。

## 当前状态

已经完成：

- SwiftUI 应用结构和主要页面重建
- TCP 设备控制协议
- NFSv3 端口映射、挂载、目录读取和文件下载
- 原始 `.CFG` 配置解析
- 基础照片拼接、视频拼接和预览降级路径
- 设备网络检查与 JSON 状态探测工具

仍需真实硬件验证或继续完善：

- 不同固件版本的 NFS 导出路径兼容性
- 真实素材上的拼接标定、接缝融合和 IMU 防抖
- Metal 实时预览和 360 播放调优
- 固件上传传输流程

## 公开仓库范围

仓库只提交我们编写和整理的源码、测试、工具及研究文档。原始 APK、APK 解包/反编译生成目录、Xcode 构建产物和本地 OAuth 客户端配置均不会提交；这些内容已通过 `.gitignore` 排除。

本项目仅用于个人研究、兼容性开发和设备互操作性测试。ORBI、Orbi 360 及相关软件/硬件名称和版权归其各自权利人所有。

## License

当前仓库暂未指定开源许可证。除非获得项目维护者明确授权，请不要将代码作为第三方产品发布或用于固件升级服务。
