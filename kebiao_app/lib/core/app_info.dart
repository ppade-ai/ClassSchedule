/// 应用信息（版本号）
///
/// 为什么手写常量：install 后读不到 pubspec.yaml。发布脚本会把这个文件
/// 与 pubspec 的版本做一致性校验，避免两处漂移。
library;

const String kAppVersion = '0.19.5';
const String kAppBuild = '16';
