# 课表 App（Timetable）

一个**离线优先、零第三方依赖**的 Android 课表应用（Flutter）。

- 不联网：发布版 APK 不含 `INTERNET` 权限，系统层面断网
- 数据本地：课表以纯文本（`|` 分隔的标准行）存在应用私有目录，可直接带走
- 插件化：学校解析规则、导入格式与 UI 解耦，新增一所学校只加数据不改内核

## 构建

```bash
flutter pub get
flutter build apk --release     # 产物：build/app/outputs/flutter-apk/app-release.apk
flutter test                    # 单元 / 组件测试
```

要求 Flutter 3.47+、JDK 17+、Android SDK 36（minSdk 26）。

> 项目路径必须为 ASCII：AGP 9 与 Dart AOT 的路径检查都会拒绝非 ASCII 路径。
> 若仓库放在中文目录下，请用目录联接（`mklink /J`）映射出一个英文路径再构建。

## 目录

```
kebiao_app/lib/
  core/       内核：模型 / 解析 / 合并引擎 / 存储（零 UI、零网络）
  ui/         界面：课表网格、编辑、批量文本、技能下载
kebiao_app/android/   安卓工程
kebiao_app/test/      测试
```

## 数据格式

课表与补丁都是纯文本行，字段以 `|` 分隔，行尾是唯一 id。
格式定义与导入方式见应用内「更多 → Skill 下载」。
