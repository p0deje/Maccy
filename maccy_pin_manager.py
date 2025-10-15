#!/usr/bin/env python3
"""
Maccy 固定条目管理工具 (完整版)

这是一个集成了导入、修复、验证和快捷键管理功能的完整工具，用于管理Maccy的固定条目。
主要功能：
1. 批量导入固定条目（支持带快捷键和无快捷键两种模式）
2. 自动检测和修复数据库中的数据完整性问题
3. 验证和统计数据库状态
4. 移除固定条目的快捷键，转换为无快捷键固定条目
5. 提供数据备份和恢复功能

使用方法：
1. 导入固定条目：python3 maccy_pin_manager.py <txt文件路径> [--with-shortcuts]
2. 移除快捷键：python3 maccy_pin_manager.py --remove-shortcuts
3. 仅修复数据库：python3 maccy_pin_manager.py --repair
4. 仅分析数据库：python3 maccy_pin_manager.py --analyze
5. 查看帮助：python3 maccy_pin_manager.py --help
"""

import sqlite3
import sys
import os
import shutil
from datetime import datetime
from pathlib import Path
import subprocess
import uuid
import argparse

class MaccyPinManager:
    def __init__(self, verbose=False):
        # Maccy数据库路径
        self.db_path = Path.home() / "Library/Application Support/Maccy/Storage.sqlite"
        self.backup_path = self.db_path.with_suffix('.sqlite.backup')

        # 详细输出模式
        self.verbose = verbose

        # 支持的固定键（与Maccy项目保持一致）
        self.supported_pins = {
            "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
            "m", "n", "o", "p", "r", "s", "t", "u", "x", "y"
        }

    def log(self, message, level="INFO"):
        """日志输出"""
        if self.verbose or level in ["ERROR", "WARNING", "SUCCESS"]:
            prefix = {
                "INFO": "ℹ️",
                "SUCCESS": "✅",
                "WARNING": "⚠️",
                "ERROR": "❌"
            }.get(level, "ℹ️")
            print(f"{prefix} {message}")

    def check_database_exists(self):
        """检查Maccy数据库是否存在"""
        if not self.db_path.exists():
            self.log(f"Maccy数据库不存在: {self.db_path}", "ERROR")
            self.log("请确保Maccy应用已安装并至少运行过一次", "ERROR")
            return False
        return True

    def check_maccy_running(self):
        """检查Maccy是否正在运行"""
        try:
            result = subprocess.run(['pgrep', 'Maccy'], capture_output=True)
            if result.returncode == 0:
                self.log("检测到Maccy正在运行", "WARNING")
                self.log("建议先关闭Maccy应用，然后重新运行此工具", "WARNING")
                return True
        except:
            pass
        return False

    def create_backup(self):
        """创建数据库备份"""
        try:
            shutil.copy2(self.db_path, self.backup_path)
            self.log(f"数据库备份已创建: {self.backup_path}", "SUCCESS")
            return True
        except Exception as e:
            self.log(f"创建备份失败: {e}", "ERROR")
            return False

    def get_used_pins(self, cursor):
        """获取已使用的固定键"""
        cursor.execute("SELECT ZPIN FROM ZHISTORYITEM WHERE ZPIN IS NOT NULL AND ZPIN != ''")
        used_pins = {row[0] for row in cursor.fetchall() if row[0]}
        return used_pins

    def get_available_pins(self, used_pins):
        """获取可用的固定键"""
        available = list(self.supported_pins - used_pins)
        available.sort()
        return available

    def fix_existing_underscore_pins(self, cursor):
        """修复数据库中使用'_'标记的固定条目"""
        cursor.execute("SELECT Z_PK FROM ZHISTORYITEM WHERE ZPIN = '_'")
        underscore_items = cursor.fetchall()

        if underscore_items:
            self.log(f"发现 {len(underscore_items)} 个使用'_'标记的固定条目，正在修复...")
            cursor.execute("UPDATE ZHISTORYITEM SET ZPIN = '' WHERE ZPIN = '_'")
            self.log(f"已修复 {len(underscore_items)} 个条目", "SUCCESS")
        return len(underscore_items)

    def check_duplicate_content(self, cursor, content):
        """检查是否存在重复内容"""
        if not content or not content.strip():
            return False
        cursor.execute("""
            SELECT COUNT(*) FROM ZHISTORYITEMCONTENT
            WHERE ZVALUE = ?
        """, (content,))
        return cursor.fetchone()[0] > 0

    def create_history_item(self, cursor, content, pin=None):
        """创建新的历史条目"""
        if not content or not content.strip():
            self.log("跳过空内容", "WARNING")
            return None

        now = datetime.now()
        # SwiftData使用的时间戳格式（从2001年1月1日开始的秒数）
        timestamp = (now - datetime(2001, 1, 1)).total_seconds()

        # 生成标题（取前100个字符，保持单行显示）
        title = content.replace('\n', ' ').strip()[:100]
        if not title:
            title = "无标题"

        # 对于无快捷键的固定条目，使用空字符串而不是特殊标记
        actual_pin = pin if pin else ""

        # 插入HistoryItem
        cursor.execute("""
            INSERT INTO ZHISTORYITEM (
                Z_PK, Z_ENT, Z_OPT, ZAPPLICATION, ZFIRSTCOPIEDAT, ZLASTCOPIEDAT,
                ZNUMBEROFCOPIES, ZPIN, ZTITLE
            ) VALUES (
                NULL, 1, 1, ?, ?, ?, 1, ?, ?
            )
        """, ("com.maccy.import", timestamp, timestamp, actual_pin, title))

        item_id = cursor.lastrowid

        # 插入HistoryItemContent (文本内容) - 使用事务确保数据完整性
        cursor.execute("""
            INSERT INTO ZHISTORYITEMCONTENT (
                Z_PK, Z_ENT, Z_OPT, ZTYPE, ZVALUE, ZITEM
            ) VALUES (
                NULL, 2, 1, ?, ?, ?
            )
        """, ("public.utf8-plain-text", content, item_id))

        # 验证插入是否成功
        cursor.execute("SELECT COUNT(*) FROM ZHISTORYITEMCONTENT WHERE ZITEM = ?", (item_id,))
        content_count = cursor.fetchone()[0]

        if content_count == 0:
            raise Exception(f"Failed to create content record for item {item_id}")

        return item_id

    def analyze_database(self):
        """分析数据库状态"""
        if not self.check_database_exists():
            return None

        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        try:
            # 检查总体数据量
            cursor.execute("SELECT COUNT(*) FROM ZHISTORYITEM")
            total_items = cursor.fetchone()[0]

            cursor.execute("SELECT COUNT(*) FROM ZHISTORYITEMCONTENT")
            total_contents = cursor.fetchone()[0]

            # 检查固定条目（包括空字符串pin）
            cursor.execute("SELECT COUNT(*) FROM ZHISTORYITEM WHERE ZPIN IS NOT NULL")
            pinned_items = cursor.fetchone()[0]

            # 检查丢失content的固定条目
            cursor.execute("""
                SELECT COUNT(*) FROM ZHISTORYITEM hi
                LEFT JOIN ZHISTORYITEMCONTENT hic ON hi.Z_PK = hic.ZITEM
                WHERE hi.ZPIN IS NOT NULL
                AND (hic.ZVALUE IS NULL OR hic.ZVALUE = '')
            """)
            broken_items = cursor.fetchone()[0]

            # 检查使用'_'标记的条目
            cursor.execute("SELECT COUNT(*) FROM ZHISTORYITEM WHERE ZPIN = '_'")
            underscore_items = cursor.fetchone()[0]

            # 检查有快捷键的固定条目
            cursor.execute("SELECT COUNT(*) FROM ZHISTORYITEM WHERE ZPIN IN ({})".format(
                ','.join(["'{}'".format(pin) for pin in self.supported_pins])
            ))
            shortcut_items = cursor.fetchone()[0]

            stats = {
                'total_items': total_items,
                'total_contents': total_contents,
                'pinned_items': pinned_items,
                'broken_items': broken_items,
                'underscore_items': underscore_items,
                'shortcut_items': shortcut_items
            }

            self.log("数据库分析结果:")
            self.log(f"  总历史条目: {total_items}")
            self.log(f"  总内容记录: {total_contents}")
            self.log(f"  固定条目: {pinned_items}")
            self.log(f"  有快捷键的固定条目: {shortcut_items}")
            self.log(f"  无快捷键的固定条目: {pinned_items - shortcut_items}")
            if broken_items > 0:
                self.log(f"  丢失内容的固定条目: {broken_items}", "WARNING")
            if underscore_items > 0:
                self.log(f"  使用'_'标记的条目: {underscore_items}", "WARNING")

            return stats

        finally:
            conn.close()

    def get_broken_items(self):
        """获取丢失内容的固定条目"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        try:
            cursor.execute("""
                SELECT hi.Z_PK, hi.ZTITLE, hi.ZAPPLICATION
                FROM ZHISTORYITEM hi
                LEFT JOIN ZHISTORYITEMCONTENT hic ON hi.Z_PK = hic.ZITEM
                WHERE hi.ZPIN IS NOT NULL
                AND (hic.ZVALUE IS NULL OR hic.ZVALUE = '')
                ORDER BY hi.Z_PK
            """)

            broken_items = cursor.fetchall()
            return broken_items

        finally:
            conn.close()

    def repair_item(self, item_id, title):
        """修复单个条目 - 从title恢复content"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        try:
            # 检查是否已经有content记录
            cursor.execute("SELECT COUNT(*) FROM ZHISTORYITEMCONTENT WHERE ZITEM = ?", (item_id,))
            existing_count = cursor.fetchone()[0]

            if existing_count == 0:
                # 创建新的content记录
                cursor.execute("""
                    INSERT INTO ZHISTORYITEMCONTENT (
                        Z_PK, Z_ENT, Z_OPT, ZTYPE, ZVALUE, ZITEM
                    ) VALUES (
                        NULL, 2, 1, ?, ?, ?
                    )
                """, ("public.utf8-plain-text", title, item_id))

                self.log(f"修复条目 {item_id}: {title[:50]}...", "SUCCESS")
                return True
            else:
                # 更新现有的content记录
                cursor.execute("""
                    UPDATE ZHISTORYITEMCONTENT
                    SET ZVALUE = ?, ZTYPE = ?
                    WHERE ZITEM = ?
                """, (title, "public.utf8-plain-text", item_id))

                self.log(f"更新条目 {item_id}: {title[:50]}...", "SUCCESS")
                return True

        except Exception as e:
            self.log(f"修复条目 {item_id} 失败: {e}", "ERROR")
            return False

        finally:
            conn.commit()
            conn.close()

    def repair_database(self):
        """修复数据库中的所有问题"""
        if not self.check_database_exists():
            return False

        # 创建备份
        self.log("正在创建数据库备份...")
        if not self.create_backup():
            self.log("备份失败，终止修复", "ERROR")
            return False

        # 修复现有数据库中的问题
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        try:
            # 修复使用'_'标记的条目
            self.fix_existing_underscore_pins(cursor)

            # 修复丢失内容的条目
            broken_items = self.get_broken_items()

            if not broken_items:
                self.log("没有发现需要修复的条目", "SUCCESS")
                conn.commit()
                conn.close()
                return True

            self.log(f"发现 {len(broken_items)} 个需要修复的条目")

            repaired_count = 0
            for item_id, title, application in broken_items:
                if self.repair_item(item_id, title):
                    repaired_count += 1

            self.log(f"修复完成! 成功修复 {repaired_count}/{len(broken_items)} 个条目", "SUCCESS")

        except Exception as e:
            self.log(f"修复过程中出现错误: {e}", "ERROR")
            conn.rollback()
            return False

        finally:
            conn.close()

        # 验证修复结果
        return self.verify_repair()

    def verify_repair(self):
        """验证修复结果"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        try:
            cursor.execute("""
                SELECT COUNT(*) FROM ZHISTORYITEM hi
                LEFT JOIN ZHISTORYITEMCONTENT hic ON hi.Z_PK = hic.ZITEM
                WHERE hi.ZPIN IS NOT NULL
                AND (hic.ZVALUE IS NULL OR hic.ZVALUE = '')
            """)

            remaining_broken = cursor.fetchone()[0]

            if remaining_broken == 0:
                self.log("修复验证成功 - 所有固定条目都有完整的内容", "SUCCESS")
                return True
            else:
                self.log(f"修复验证失败 - 仍有 {remaining_broken} 个条目缺少内容", "ERROR")
                return False

        finally:
            conn.close()

    def remove_shortcuts(self):
        """移除所有固定条目的快捷键，转换为无快捷键固定条目"""
        if not self.check_database_exists():
            return False

        # 创建备份
        self.log("正在创建数据库备份...")
        if not self.create_backup():
            self.log("备份失败，终止操作", "ERROR")
            return False

        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        try:
            # 获取有快捷键的固定条目
            cursor.execute("SELECT COUNT(*) FROM ZHISTORYITEM WHERE ZPIN IN ({})".format(
                ','.join(["'{}'".format(pin) for pin in self.supported_pins])
            ))
            shortcut_count = cursor.fetchone()[0]

            if shortcut_count == 0:
                self.log("没有发现需要移除快捷键的固定条目", "SUCCESS")
                return True

            self.log(f"发现 {shortcut_count} 个有快捷键的固定条目，正在移除快捷键...")

            # 获取具体的条目信息
            cursor.execute("""
                SELECT Z_PK, ZPIN, ZTITLE
                FROM ZHISTORYITEM
                WHERE ZPIN IN ({})
                ORDER BY ZPIN
            """.format(','.join(["'{}'".format(pin) for pin in self.supported_pins])))

            shortcut_items = cursor.fetchall()

            # 移除快捷键（设置为空字符串）
            cursor.execute("""
                UPDATE ZHISTORYITEM
                SET ZPIN = ''
                WHERE ZPIN IN ({})
            """.format(','.join(["'{}'".format(pin) for pin in self.supported_pins])))

            # 显示被移除快捷键的条目
            for item_id, old_pin, title in shortcut_items:
                self.log(f"已移除快捷键 [{old_pin}]: {title[:50]}{'...' if len(title) > 50 else ''}")

            self.log(f"成功移除 {len(shortcut_items)} 个固定条目的快捷键", "SUCCESS")
            self.log("所有条目现在都是无快捷键的固定条目", "SUCCESS")

            # 验证操作结果
            cursor.execute("SELECT COUNT(*) FROM ZHISTORYITEM WHERE ZPIN IN ({})".format(
                ','.join(["'{}'".format(pin) for pin in self.supported_pins])
            ))
            remaining_shortcuts = cursor.fetchone()[0]

            cursor.execute("SELECT COUNT(*) FROM ZHISTORYITEM WHERE ZPIN = ''")
            empty_pin_count = cursor.fetchone()[0]

            if remaining_shortcuts == 0:
                self.log(f"验证成功: 剩余 {empty_pin_count} 个无快捷键固定条目", "SUCCESS")
                conn.commit()
                return True
            else:
                self.log(f"验证失败: 仍有 {remaining_shortcuts} 个条目有快捷键", "ERROR")
                conn.rollback()
                return False

        except Exception as e:
            self.log(f"移除快捷键过程中出现错误: {e}", "ERROR")
            conn.rollback()
            return False

        finally:
            conn.close()

    def import_from_file(self, file_path, assign_shortcuts=False):
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

            for line in content.splitlines():
                stripped_line = line.rstrip()
                if stripped_line:  # 非空行
                    current_entry.append(stripped_line)
                else:  # 空行，结束当前条目
                    if current_entry:
                        # 保留原始格式，不合并多行
                        entries.append('\n'.join(current_entry))
                        current_entry = []

            # 处理最后一个条目（如果文件末尾没有空行）
            if current_entry:
                entries.append('\n'.join(current_entry))

            # 如果没有空白行，每行作为一个条目
            if not entries and content.strip():
                entries = [line.rstrip() for line in content.splitlines() if line.strip()]

            # 过滤掉空条目
            lines = [entry for entry in entries if entry and entry.strip()]

        except Exception as e:
            self.log(f"读取文件失败: {e}", "ERROR")
            return False

        if not lines:
            self.log("文件为空或没有有效内容", "ERROR")
            return False

        self.log(f"找到 {len(lines)} 个条目待导入")

        # 连接数据库
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()

            # 修复现有数据库中的问题
            self.fix_existing_underscore_pins(cursor)

            available_pins = []
            if assign_shortcuts:
                # 获取已使用的固定键
                used_pins = self.get_used_pins(cursor)
                self.log(f"已使用的固定键: {sorted(used_pins)}")

                # 获取可用的固定键
                available_pins = self.get_available_pins(used_pins)
                self.log(f"可用的固定键: {available_pins}")

                if not available_pins:
                    self.log("没有可用的固定键", "ERROR")
                    return False
            else:
                self.log("模式：导入为固定条目（无快捷键）")

            imported_count = 0
            skipped_count = 0
            shortcut_count = 0

            for i, line in enumerate(lines):
                # 跳过空内容
                if not line or not line.strip():
                    skipped_count += 1
                    continue

                # 检查重复内容
                if self.check_duplicate_content(cursor, line):
                    display_text = line.replace('\n', ' ')[:50]
                    self.log(f"跳过重复条目: {display_text}{'...' if len(line) > 50 else ''}")
                    skipped_count += 1
                    continue

                # 分配快捷键（如果启用且有可用键）
                pin = None
                if assign_shortcuts and available_pins:
                    pin = available_pins.pop(0)
                    shortcut_count += 1

                try:
                    item_id = self.create_history_item(cursor, line, pin)
                    if item_id is None:
                        skipped_count += 1
                        continue

                    display_text = line.replace('\n', ' ')[:50]
                    if pin:
                        self.log(f"导入固定条目 [{pin}]: {display_text}{'...' if len(line) > 50 else ''}")
                    else:
                        self.log(f"导入固定条目 (无快捷键): {display_text}{'...' if len(line) > 50 else ''}")
                    imported_count += 1
                except Exception as e:
                    self.log(f"创建条目失败: {e}", "ERROR")
                    skipped_count += 1
                    continue

            # 提交事务
            conn.commit()

            # 验证数据完整性
            self.log("验证数据完整性...")
            cursor.execute("""
                SELECT COUNT(*) FROM ZHISTORYITEM hi
                LEFT JOIN ZHISTORYITEMCONTENT hic ON hi.Z_PK = hic.ZITEM
                WHERE hi.ZAPPLICATION = 'com.maccy.import'
                AND (hic.ZVALUE IS NULL OR hic.ZVALUE = '')
            """)
            broken_count = cursor.fetchone()[0]

            if broken_count > 0:
                self.log(f"警告: 发现 {broken_count} 个导入的条目缺少内容", "WARNING")
                self.log("这可能是因为数据库操作问题，正在自动修复...")

                # 自动修复这些问题
                conn.close()
                success = self.repair_database()
                if not success:
                    self.log("自动修复失败，请手动运行修复功能", "ERROR")
                    return False
            else:
                self.log("所有导入的条目都有完整的内容", "SUCCESS")

            self.log("导入完成!", "SUCCESS")
            self.log(f"成功导入: {imported_count} 个条目")
            if shortcut_count > 0:
                self.log(f"分配快捷键: {shortcut_count} 个")
            self.log(f"跳过条目: {skipped_count} 个")
            self.log("请重启Maccy应用以查看导入的固定条目")

            return True

        except Exception as e:
            self.log(f"数据库操作失败: {e}", "ERROR")
            return False
        finally:
            if 'conn' in locals():
                conn.close()

    def run_full_workflow(self, file_path=None, assign_shortcuts=False):
        """运行完整的工作流程：导入 -> 修复 -> 验证"""
        self.log("Maccy 固定条目管理工具", "SUCCESS")
        self.log("=" * 50)

        # 检查数据库状态
        stats = self.analyze_database()
        if stats is None:
            return False

        # 如果需要导入文件
        if file_path:
            if not os.path.exists(file_path):
                self.log(f"文件不存在: {file_path}", "ERROR")
                return False

            # 检查Maccy是否正在运行
            if self.check_maccy_running():
                response = input("是否继续？(y/N): ")
                if response.lower() != 'y':
                    self.log("已取消操作")
                    return False

            # 创建备份
            self.log("正在创建数据库备份...")
            if not self.create_backup():
                self.log("备份失败，终止操作", "ERROR")
                return False

            # 导入固定条目
            self.log("开始导入固定条目...")
            if not self.import_from_file(file_path, assign_shortcuts):
                self.log("导入失败", "ERROR")
                return False

        # 修复数据库问题
        if stats['broken_items'] > 0 or stats['underscore_items'] > 0:
            self.log("发现数据库问题，正在修复...")
            if not self.repair_database():
                self.log("修复失败", "ERROR")
                return False

        # 最终验证
        self.log("最终验证...")
        final_stats = self.analyze_database()
        if final_stats is None:
            return False

        if final_stats['broken_items'] == 0 and final_stats['underscore_items'] == 0:
            self.log("所有操作完成，数据库状态正常", "SUCCESS")
            return True
        else:
            self.log("数据库仍存在问题，请检查日志", "ERROR")
            return False

def main():
    parser = argparse.ArgumentParser(
        description="Maccy 固定条目管理工具 - 集成导入、修复和验证功能",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  # 导入固定条目（无快捷键）
  python3 maccy_pin_manager.py pins.txt

  # 导入固定条目（带快捷键）
  python3 maccy_pin_manager.py pins.txt --with-shortcuts

  # 移除所有固定条目的快捷键
  python3 maccy_pin_manager.py --remove-shortcuts

  # 仅修复数据库
  python3 maccy_pin_manager.py --repair

  # 仅分析数据库
  python3 maccy_pin_manager.py --analyze

  # 详细输出模式
  python3 maccy_pin_manager.py pins.txt --verbose
        """
    )

    parser.add_argument('file', nargs='?', help='要导入的文本文件路径')
    parser.add_argument('--with-shortcuts', action='store_true',
                       help='为导入的条目分配快捷键')
    parser.add_argument('--repair', action='store_true',
                       help='仅修复数据库问题')
    parser.add_argument('--analyze', action='store_true',
                       help='仅分析数据库状态')
    parser.add_argument('--remove-shortcuts', action='store_true',
                       help='移除所有固定条目的快捷键，转换为无快捷键固定条目')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='详细输出模式')

    args = parser.parse_args()

    # 创建管理器实例
    manager = MaccyPinManager(verbose=args.verbose)

    # 执行相应的操作
    if args.repair:
        success = manager.repair_database()
    elif args.analyze:
        stats = manager.analyze_database()
        success = stats is not None
    elif args.remove_shortcuts:
        success = manager.remove_shortcuts()
    elif args.file:
        success = manager.run_full_workflow(args.file, args.with_shortcuts)
    else:
        parser.print_help()
        sys.exit(1)

    if not success:
        sys.exit(1)

if __name__ == "__main__":
    main()