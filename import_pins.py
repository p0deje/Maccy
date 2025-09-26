#!/usr/bin/env python3
"""
Maccy 固定条目批量导入工具 (Python版本)

这个脚本通过直接操作SQLite数据库来批量导入固定条目。
支持两种模式：
1. 带快捷键的固定条目（最多21个）
2. 无快捷键的固定条目（无数量限制）

使用前请确保Maccy应用已关闭，以避免数据库锁定问题。
"""

import sqlite3
import sys
import os
from datetime import datetime
from pathlib import Path
import uuid

class MaccyPinImporter:
    def __init__(self, assign_shortcuts=False):
        # Maccy数据库路径
        self.db_path = Path.home() / "Library/Application Support/Maccy/Storage.sqlite"
        
        # 是否分配快捷键
        self.assign_shortcuts = assign_shortcuts
        
        # 支持的固定键（与Maccy项目保持一致）
        self.supported_pins = {
            "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
            "m", "n", "o", "p", "r", "s", "t", "u", "x", "y"
        }
    def check_database_exists(self):
        """检查Maccy数据库是否存在"""
        if not self.db_path.exists():
            print(f"❌ Maccy数据库不存在: {self.db_path}")
            print("💡 请确保Maccy应用已安装并至少运行过一次")
            return False
        return True
    
    def get_used_pins(self, cursor):
        """获取已使用的固定键"""
        cursor.execute("SELECT ZPIN FROM ZHISTORYITEM WHERE ZPIN IS NOT NULL")
        used_pins = {row[0] for row in cursor.fetchall() if row[0]}
        return used_pins
    
    def get_available_pins(self, used_pins):
        """获取可用的固定键"""
        available = list(self.supported_pins - used_pins)
        available.sort()
        return available
    
    def check_duplicate_content(self, cursor, content):
        """检查是否存在重复内容"""
        cursor.execute("""
            SELECT COUNT(*) FROM ZHISTORYITEMCONTENT 
            WHERE ZVALUE = ?
        """, (content.encode('utf-8'),))
        return cursor.fetchone()[0] > 0
    
    def create_history_item(self, cursor, content, pin=None):
        """创建新的历史条目"""
        now = datetime.now()
        # SwiftData使用的时间戳格式（从2001年1月1日开始的秒数）
        timestamp = (now - datetime(2001, 1, 1)).total_seconds()
        
        # 生成标题（取前100个字符，保持单行显示）
        title = content.replace('\n', ' ').strip()[:100]
        
        # 对于无快捷键的固定条目，使用特殊标记
        actual_pin = pin if pin else "_"
        
        # 插入HistoryItem
        cursor.execute("""
            INSERT INTO ZHISTORYITEM (
                Z_PK, Z_ENT, Z_OPT, ZAPPLICATION, ZFIRSTCOPIEDAT, ZLASTCOPIEDAT,
                ZNUMBEROFCOPIES, ZPIN, ZTITLE
            ) VALUES (
                NULL, 1, 1, ?, ?, ?, 1, ?, ?
            )
        """, ("PinImporter", timestamp, timestamp, actual_pin, title))
        
        item_id = cursor.lastrowid
        
        # 插入HistoryItemContent (文本内容)
        cursor.execute("""
            INSERT INTO ZHISTORYITEMCONTENT (
                Z_PK, Z_ENT, Z_OPT, ZTYPE, ZVALUE, ZITEM
            ) VALUES (
                NULL, 2, 1, ?, ?, ?
            )
        """, ("public.utf8-plain-text", content.encode('utf-8'), item_id))
        
        return item_id
    
    def import_from_file(self, file_path):
        """从文件导入固定条目"""
        if not self.check_database_exists():
            return False
        
        # 读取文件内容并按空白行分割
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # 按空白行分割内容，每个部分作为一个条目
            entries = []
            current_entry = []
            
            for line in content.split('\n'):
                line = line.strip()
                if line:  # 非空行
                    current_entry.append(line)
                else:  # 空行，结束当前条目
                    if current_entry:
                        entries.append('\n'.join(current_entry))
                        current_entry = []
            
            # 处理最后一个条目（如果文件末尾没有空行）
            if current_entry:
                entries.append('\n'.join(current_entry))
            
            lines = entries
            
        except Exception as e:
            print(f"❌ 读取文件失败: {e}")
            return False
        
        if not lines:
            print("❌ 文件为空或没有有效内容")
            return False
        
        print(f"📝 找到 {len(lines)} 个条目待导入")
        
        # 连接数据库
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            available_pins = []
            if self.assign_shortcuts:
                # 获取已使用的固定键
                used_pins = self.get_used_pins(cursor)
                print(f"🔑 已使用的固定键: {sorted(used_pins)}")
                
                # 获取可用的固定键
                available_pins = self.get_available_pins(used_pins)
                print(f"✅ 可用的固定键: {available_pins}")
                
                if not available_pins:
                    print("❌ 没有可用的固定键")
                    return False
            else:
                print("🔧 模式：导入为固定条目（无快捷键）")
            
            imported_count = 0
            skipped_count = 0
            shortcut_count = 0
            
            for i, line in enumerate(lines):
                # 检查重复内容
                if self.check_duplicate_content(cursor, line):
                    display_text = line.replace('\n', ' ')[:50]
                    print(f"⏭️  跳过重复条目: {display_text}{'...' if len(line) > 50 else ''}")
                    skipped_count += 1
                    continue
                
                # 分配快捷键（如果启用且有可用键）
                pin = None
                if self.assign_shortcuts and available_pins:
                    pin = available_pins.pop(0)
                    shortcut_count += 1
                
                try:
                    item_id = self.create_history_item(cursor, line, pin)
                    display_text = line.replace('\n', ' ')[:50]
                    if pin:
                        print(f"📌 导入固定条目 [{pin}]: {display_text}{'...' if len(line) > 50 else ''}")
                    else:
                        print(f"📌 导入固定条目 (无快捷键): {display_text}{'...' if len(line) > 50 else ''}")
                    imported_count += 1
                except Exception as e:
                    print(f"❌ 创建条目失败: {e}")
                    skipped_count += 1
                    continue
            
            # 提交事务
            conn.commit()
            
            print(f"\n🎉 导入完成!")
            print(f"✅ 成功导入: {imported_count} 个条目")
            if shortcut_count > 0:
                print(f"🔑 分配快捷键: {shortcut_count} 个")
            print(f"⏭️  跳过条目: {skipped_count} 个")
            print(f"💡 请重启Maccy应用以查看导入的固定条目")
            
            return True
            
        except Exception as e:
            print(f"❌ 数据库操作失败: {e}")
            return False
        finally:
            if 'conn' in locals():
                conn.close()

def main():
    print("🚀 Maccy 固定条目批量导入工具 (Python版)")
    print("=" * 50)
    
    if len(sys.argv) < 2 or len(sys.argv) > 3:
        print("❌ 使用方法: python3 import_pins.py <txt文件路径> [--with-shortcuts]")
        print("📝 示例: python3 import_pins.py ~/Desktop/pins.txt")
        print("📝 带快捷键: python3 import_pins.py ~/Desktop/pins.txt --with-shortcuts")
        print("")
        print("🔧 模式说明:")
        print("   默认模式: 导入所有条目为固定条目（无快捷键，无数量限制）")
        print("   --with-shortcuts: 为前21个条目分配快捷键")
        sys.exit(1)
    
    file_path = sys.argv[1]
    assign_shortcuts = len(sys.argv) == 3 and sys.argv[2] == "--with-shortcuts"
    
    # 检查文件是否存在
    if not os.path.exists(file_path):
        print(f"❌ 文件不存在: {file_path}")
        sys.exit(1)
    
    # 检查Maccy是否正在运行
    import subprocess
    try:
        result = subprocess.run(['pgrep', 'Maccy'], capture_output=True)
        if result.returncode == 0:
            print("⚠️  检测到Maccy正在运行")
            print("💡 建议先关闭Maccy应用，然后重新运行此脚本")
            response = input("是否继续？(y/N): ")
            if response.lower() != 'y':
                print("👋 已取消导入")
                sys.exit(0)
    except:
        pass  # 忽略检查错误
    
    # 执行导入
    importer = MaccyPinImporter(assign_shortcuts=assign_shortcuts)
    success = importer.import_from_file(file_path)
    
    if success:
        print("\n🎯 导入成功！下次打开Maccy时即可看到新的固定条目")
    else:
        print("\n💥 导入失败，请检查错误信息")
        sys.exit(1)

if __name__ == "__main__":
    main()