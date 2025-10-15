# Maccy 固定条目批量导入指南

## 概述

这个工具允许您批量导入固定条目到Maccy，支持两种模式：

1. **无快捷键模式**（默认）：导入所有条目为固定条目，不分配快捷键，无数量限制
2. **带快捷键模式**：为前21个条目分配快捷键（b, c, d, e...等）

## 使用方法

### 基本用法

```bash
# 无快捷键模式（推荐用于大量条目）
python3 import_pins.py ~/Desktop/pins.txt

# 带快捷键模式（最多21个）
python3 import_pins.py ~/Desktop/pins.txt --with-shortcuts
```

### 文件格式

创建一个纯文本文件（.txt），每个条目之间用空行分隔：

```
条目1内容
可以包含多行文本

条目2内容
这是另一个条目

条目3内容
```

### 注意事项

1. **关闭Maccy**：导入前请确保Maccy应用已关闭，避免数据库锁定
2. **备份数据**：建议先备份数据库文件：`~/Library/Application Support/Maccy/Storage.sqlite`
3. **重启应用**：导入完成后需要重启Maccy才能看到新条目
4. **去重功能**：脚本会自动跳过重复内容

## 技术实现

### 无快捷键固定条目的实现

- 使用特殊字符 `"_"` 作为无快捷键固定条目标识
- 该字符不在Maccy支持的快捷键字符集中，不会冲突
- 在设置界面中显示为 `"-"`，保持界面整洁

### 数据库结构

- 固定条目通过 `ZPIN` 字段标识（非NULL即为固定条目）
- 无快捷键条目使用 `"_"` 作为占位符
- 不影响现有的快捷键分配逻辑

## 故障排除

### 常见问题

1. **数据库锁定**：确保Maccy已完全退出
2. **权限问题**：检查是否有写入数据库的权限
3. **条目不显示**：重启Maccy应用

### 验证导入

导入完成后：
1. 重启Maccy应用
2. 打开偏好设置 → 固定条目
3. 检查所有导入的条目是否显示在列表中
4. 无快捷键条目会显示为 `"-"`

## 示例

### 创建测试文件

```bash
cat > test_pins.txt << EOF
常用邮箱地址
user@example.com

常用GitHub仓库
https://github.com/user/repo

常用代码片段
console.log('Hello World');
EOF
```

### 导入测试

```bash
# 无快捷键模式
python3 import_pins.py test_pins.txt

# 带快捷键模式（前3个分配快捷键）
python3 import_pins.py test_pins.txt --with-shortcuts