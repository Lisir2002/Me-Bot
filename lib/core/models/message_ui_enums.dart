/// 一条消息在「同一发送者连续消息簇」中的位置
enum MessageClusterPosition {
  single, // 簇内只有这一条
  head, // 簇首（>1 条时的第一条）
  middle, // 簇中间
  tail, // 簇尾（最后一条）
}

/// 用户消息发送状态机
enum MessageSendStatus {
  sending, // 发送中：时钟图标，整体 0.7 透明
  sent, // 已发送：单勾
  delivered, // 已送达：双勾（中性色）
  read, // 已读：双勾（主题色着色）
  failed, // 失败：红色图标，点击触发重发
}

/// 助手回复详细度（控制思考块/工具块默认展开折叠）
enum VerbosityMode {
  simple, // 思考块、工具块默认均折叠
  thinking, // 思考块默认展开、工具块默认折叠（默认档）
  verbose, // 思考块、工具块默认均展开
}
