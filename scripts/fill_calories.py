#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
fill_calories.py
================
填补 Kitchen iOS App 中缺失的 calories 数据。

策略 A + B：
  A. 菜名关键词查表（命中 80%+ 主流菜型）
  B. 食材反推（基于中国食物成分表 + 标准克重映射）

数据来源：CookBook-KG (https://github.com/ngl567/CookBook-KG)
原始 KG 不含营养字段，本脚本基于公开营养数据库（USDA / 中国食物成分表）估算。

用法：
  python3 fill_calories.py              # 干跑预览（不写文件）
  python3 fill_calories.py --apply     # 实际回写 JSON
  python3 fill_calories.py --only=name # 只处理某菜（精确匹配 name）
  python3 fill_calories.py --report    # 写完后生成 csv 报告
"""

import os
import sys
import json
import re
import argparse
import csv
from collections import defaultdict, Counter
from pathlib import Path

ROOT = Path("/Users/hengmintao/Desktop/Kitchen/Kitchen/Recipes")

# ============================================================================
# A. 菜名关键词查表
#    每条 (正则模式, per-serving 千卡数, 说明)
#    ⚠️ 千卡单位 = kcal per person per serving （与现有人工数据一致：
#       congyoubanmian 葱油拌面 2人份 总 700kcal → 350/person）
#    多菜型放在前面以优先匹配。
# ============================================================================

# 单位说明：calories 字段是 "每人" 的千卡 / 大卡，不是整道菜的总量。
# 以 2 人份家常菜为基准估算：主料 + 配菜 + 油脂 + 糖。

DISH_PATTERNS = [
    # ───────── 川菜 (水煮/鱼香系列) ─────────
    (r"麻辣水煮鱼|超麻辣水煮鱼|椒麻水煮鱼|麻辣飘香水煮鱼",          260, "水煮鱼麻辣款偏油"),
    (r"水煮鱼|水煮活鱼|水煮龙利鱼|水煮鱼块|水煮鱼片|水煮豆腐鱼", 240, "水煮鱼标准"),
    (r"番茄水煮鱼|小清新版水煮鱼|黄芪水煮鱼|重庆水煮鱼|正宗川菜水煮鱼", 220, "水煮鱼清淡/番茄款"),
    (r"重庆水煮酸菜鱼",                                              230, "酸菜鱼"),
    (r"水煮牛肉片",                                                   260, "水煮牛肉"),
    (r"水煮羊肉片",                                                   270, "水煮羊肉"),
    (r"水煮肉片|麻辣水煮肉片|懒人水煮肉片|川味水煮肉片|私房水煮肉片|清香版水煮肉片", 270, "水煮肉片标准"),
    (r"家常水煮肉片|家庭版.*水煮肉|家.*水煮肉",                     260, "家常水煮肉片"),
    (r"鱼香肉丝|鱼.*香.*肉丝|杏鲍菇鱼香肉丝|素鱼香肉丝",          210, "鱼香肉丝"),

    # ───────── 浙菜/粤菜/家常 (糖醋系列) ─────────
    (r"糖醋排骨|糖醋.*排骨",                                          280, "糖醋排骨"),
    (r"广式糖醋排骨",                                                 290, "广式糖醋排骨"),
    (r"无油版糖醋排骨",                                               230, "糖醋排骨少油"),
    (r"橙香糖醋排骨|菠萝糖醋排骨|生炒糖醋排骨|红烧糖醋排骨|糖醋焖排骨|糖醋烤排骨|糖醋素排骨|糖醋小排骨|芜湖糖醋排骨|懒人版糖醋排骨", 280, "糖醋排骨变体"),

    # ───────── 家常 (红烧肉/红烧排骨) ─────────
    (r"红烧肉",                                                       290, "红烧肉标准"),
    (r"毛家红烧肉|毛氏红烧肉",                                        320, "毛家红烧肉"),
    (r"红烧排骨",                                                     260, "红烧排骨"),
    (r"红烧排骨炖土豆|红烧排骨胡萝卜|红烧排骨千张结|红烧排骨饭|红烧排骨面|红烧紫薯排骨|土豆红烧排骨|蒜香红烧排骨|秘制红烧排骨", 270, "红烧排骨+配菜"),
    (r"红烧鱼.*饭|红烧鱼.*面|红烧鱼.*豆腐|红烧鱼头",               200, "红烧鱼带主食"),
    (r"红烧鱼头炖豆腐",                                               220, "鱼头豆腐"),
    (r"红烧鱼",                                                       180, "红烧鱼"),
    (r"红烧鲅鱼|红烧鳊鱼|红烧黄刺鱼|红烧黄骨鱼|红烧鲳鱼|红烧金鲳鱼|红烧金昌鱼|红烧桂鱼|红烧福寿鱼|红烧海参斑鱼|红烧瓦块鱼|红烧昂刺鱼|红烧扒皮鱼|红烧杂鱼|红烧安康鱼|红烧多宝鱼", 200, "红烧海鱼"),
    (r"啤酒红烧鱼|十分钟红烧鱼",                                     180, "红烧鱼简化版"),
    (r"山楂红烧肉|栗子红烧肉|桂香红烧肉|笋干红烧肉|海参红烧肉|红烧肉炖土豆|红烧肉炖蛋|红烧肉焖饭|芋头红烧肉|莲子红烧肉|萝卜红烧肉|笋干红烧肉", 310, "红烧肉带配菜"),
    (r"苏式红烧肉|本帮红烧肉|上海红烧肉|上海秘制红烧肉|外婆红烧肉|老佛爷红烧肉", 310, "本帮红烧肉偏甜"),
    (r"腐乳红烧肉|无油红烧肉|无酱油版红烧肉|肥而不腻红烧肉|高压锅版红烧肉|改良版.*红烧肉|冻豆腐红烧肉|元宝红烧肉", 260, "红烧肉减油版"),
    (r"虎皮蛋焖红烧肉",                                               320, "红烧肉+蛋"),

    # ───────── 家常 (可乐鸡翅) ─────────
    (r"可乐鸡翅",                                                     230, "可乐鸡翅标准"),
    (r"可乐姜汁鸡翅|可乐烧鸡翅|可乐鸡翅根",                         240, "可乐鸡翅变体"),
    (r"柠檬可乐鸡翅|柠香可乐鸡翅|橙香可乐鸡翅|大众可乐鸡翅|改良版可乐鸡翅|无油版可乐鸡翅|简单的可乐鸡翅|微波炉巧做可乐鸡翅|香甜可乐鸡翅", 230, "可乐鸡翅口味变体"),
    (r"汽水红烧肉",                                                   290, "汽水红烧肉类可乐"),

    # ───────── 凉菜 (几乎都是黑木耳) ─────────
    (r"凉拌.*黑木耳|黑木耳.*凉拌",                                    50,  "黑木耳凉拌"),
    (r"凉拌木耳|凉拌木耳黄瓜|凉拌洋葱黑木耳|凉拌爽脆黑木耳|凉拌花生黑木耳|凉拌金菇黑木耳|凉拌香辣黑木耳|凉拌黑木耳苦瓜|凉拌黑木耳酸辣味|西芹花生凉拌黑木耳|午餐便当凉拌木耳|凉拌三丝黑木耳", 55, "黑木耳凉拌变体"),
    (r"泡椒黑木耳|腐竹拌黑木耳",                                     70,  "黑木耳+配菜"),
    (r"剁椒拌黑木耳",                                                 80,  "湘式剁椒黑木耳"),
    (r"凉拌",                                                          80,  "其他凉拌"),
    (r"爽心木耳沙拉",                                                 90,  "木耳沙拉"),

    # ───────── 西餐 (意大利面/意面) ─────────
    (r"黑椒牛柳意",                                                   290, "黑椒牛柳意面"),
    (r"菇香牛肉意|牛肉味番茄意|牛肉意",                              270, "牛肉意面"),
    (r"黑胡椒牛排",                                                   280, "黑椒牛排"),
    (r"培根奶油意|培根白酱意|奶油培根意",                             320, "奶油培根意面最油"),
    (r"培根鲜虾意",                                                   300, "培根虾意面"),
    (r"培根意|番茄培根意|茄汁培根意|茄汁培根炒意",                   280, "培根意面"),
    (r"海鲜意|海鲜意大利面|牛油果酱海鲜意|鲜虾.*意|虾仁意",           240, "海鲜意面"),
    (r"番茄意大利面|番茄酱意大利面|番茄意大利面|黑蒜菠菜意面",        230, "番茄意面"),
    (r"番茄肉末意|番茄肉酱意|番茄肉酱烩意|番茄鲜虾意",               250, "番茄肉酱意面"),
    (r"意式肉酱面|肉酱意",                                            250, "肉酱意面"),
    (r"橙汁黑椒牛肉意",                                               280, "橙汁黑椒牛肉意面"),
    (r"咖喱酱意|咖喱.*意",                                            260, "咖喱意面"),
    (r"牛排意|蒜香意|蒜香胡椒炒意|意面|意粉|螺丝面|蝴蝶面|螺旋面|意大利.*面", 240, "标准意面"),
    (r"意大利红虾面",                                                 250, "红虾意面"),
    (r"蕃茄火腿意",                                                   270, "火腿意面"),
    (r"香椿意",                                                       220, "香椿意面"),
    (r"香浓意|香炒意|黑胡椒意|黑椒意",                                240, "意面默认"),
]


# ============================================================================
# B. 食材-热量数据库（每 100 g 的千卡数）
# 数据来源：中国食物成分表（第 6 版）+ USDA FoodData Central
# ============================================================================

INGREDIENT_KCAL_PER_100G = {
    # ── 肉类 ──
    "五花肉": 508, "排骨": 264, "猪里脊": 242, "猪瘦肉": 143, "猪蹄": 260,
    "牛肉": 250, "牛腩": 332, "牛排": 250, "牛里脊": 158, "牛柳": 158,
    "羊肉": 203, "羊排": 198,
    "鸡肉": 167, "鸡翅": 194, "鸡翅根": 184, "鸡腿": 146, "鸡胸": 133,
    "鸡翅中": 194, "鸡爪": 215,
    "鸭肉": 240, "鸭翅": 186,
    "培根": 540, "火腿": 145, "香肠": 350, "腊肠": 580,
    "五花肉末": 508, "肉末": 250, "肉馅": 250,
    # ── 海鲜/鱼 ──
    "草鱼": 113, "鲤鱼": 109, "鲫鱼": 91, "鲈鱼": 105, "带鱼": 127,
    "鲳鱼": 142, "鲅鱼": 122, "鳊鱼": 135, "多宝鱼": 102, "桂鱼": 117,
    "黄刺鱼": 138, "黄骨鱼": 138, "金鲳鱼": 142, "安康鱼": 88,
    "海参斑": 76, "瓦块鱼": 113, "福寿鱼": 96, "金昌鱼": 142,
    "昂刺鱼": 122, "扒皮鱼": 86, "杂鱼": 110, "马口鱼": 110,
    "龙利鱼": 88, "鲍鱼": 90, "虾": 90, "虾仁": 90, "鲜虾": 90,
    "蛤蜊": 40, "鱿鱼": 84,
    # ── 蔬菜 ──
    "土豆": 76, "番茄": 18, "西红柿": 18, "洋葱": 39, "胡萝卜": 41,
    "黄瓜": 15, "生菜": 13, "苦瓜": 17, "花菜": 24, "西蓝花": 33,
    "青椒": 22, "红椒": 32, "彩椒": 32, "尖椒": 22, "辣椒": 40,
    "黑木耳": 25, "木耳": 25, "银耳": 19, "金针菇": 26, "杏鲍菇": 31,
    "香菇": 19, "平菇": 20, "草菇": 23,
    "芹菜": 14, "西芹": 16, "藕": 70, "莴笋": 14, "豆芽": 21,
    "茄子": 21, "冬瓜": 11, "南瓜": 22, "豆腐": 76, "冻豆腐": 84,
    "腐竹": 459, "豆皮": 409,
    # ── 米面主食 ──
    "米饭": 130, "大米": 130, "面粉": 350, "面条": 280, "挂面": 350,
    "意大利面": 350, "意面": 350, "蝴蝶面": 350, "螺丝面": 350,
    "通心粉": 350, "细面条": 280, "米粉": 358, "年糕": 154,
    "馒头": 223, "面包": 312, "吐司": 312,
    # ── 蛋奶 ──
    "鸡蛋": 144, "蛋": 144, "蛋清": 52, "蛋黄": 322, "皮蛋": 171,
    "鸭蛋": 190, "鹌鹑蛋": 160,
    "牛奶": 54, "酸奶": 72, "奶酪": 350, "黄油": 717, "奶油": 720,
    "芝士": 350, "淡奶油": 345,
    # ── 调味/油脂/糖 ──
    "油": 900, "橄榄油": 899, "花生油": 899, "菜籽油": 899, "豆油": 899,
    "芝麻油": 898, "香油": 898, "色拉油": 884, "玉米油": 884, "亚麻籽油": 884,
    "辣椒油": 900, "红油": 900, "蚝油": 100, "豆瓣酱": 178, "甜面酱": 184,
    "番茄酱": 110, "番茄沙司": 110, "沙拉酱": 600, "千岛酱": 470,
    "酱油": 50, "老抽": 50, "生抽": 50, "蒸鱼豉油": 50, "味极鲜": 50,
    "醋": 22, "米醋": 22, "陈醋": 26, "香醋": 26, "白醋": 6,
    "料酒": 35, "黄酒": 90, "啤酒": 32,
    "白糖": 387, "冰糖": 387, "糖": 387, "红糖": 389, "蜂蜜": 321,
    "盐": 0, "鸡精": 200, "味精": 174, "胡椒粉": 250,
    "五香粉": 280, "十三香": 280, "花椒粉": 290, "辣椒粉": 320,
    "花椒": 280, "八角": 250, "桂皮": 200, "香叶": 200, "茴香": 220,
    "孜然": 350, "咖喱粉": 330,
    # ── 水果/坚果 ──
    "苹果": 52, "梨": 44, "山楂": 95, "柠檬": 37, "橙子": 47,
    "花生": 567, "腰果": 552, "核桃": 654, "杏仁": 579, "开心果": 557,
    "芝麻": 565, "白芝麻": 565, "黑芝麻": 531,
    "椰浆": 200, "椰奶": 200, "牛油果": 160,
    # ── 其他 ──
    "黑蒜": 120, "香椿": 50, "笋": 19, "笋干": 80, "香干": 410,
    "雪菜": 33, "酸菜": 33, "泡椒": 24, "剁椒": 24,
}


# "适量" 默认克重推断（家庭做菜典型用量）
DEFAULT_AMOUNTS = {
    # 主料类 — 按一份菜的人均基准
    "main_meat": 150,        # 肉/人份 中等份量
    "fish_main": 250,        # 鱼/菜（如果主要食材）
    "pasta": 100,            # 意面/人份（一份约 100g 干面 = ~350 kcal 淀粉）
    "fungus": 30,            # 木耳等菌菇
    # 调料类 — 整道菜 (够 2 人份)
    "oil_per_dish": 25,      # 油 ml/菜
    "salt_per_dish": 4,      # 盐 g/菜
    "sugar_per_dish": 10,    # 糖 g/菜 （糖醋类会更高）
    "soy_per_dish": 15,      # 酱油 ml/菜
    "wine_per_dish": 10,     # 料酒 ml/菜
    "small_aroma_g_per_dish": 5,  # 葱姜蒜八角等
    # 蔬菜
    "veg_per_dish": 150,     # 一道菜蔬菜量
}


def estimate_grams_for_name(name: str, is_main: bool) -> float:
    """根据食材中文名推断典型用量（克）。"""
    if not is_main:
        # 调料类
        if any(k in name for k in ["盐", "糖", "白糖", "冰糖"]):
            return DEFAULT_AMOUNTS["salt_per_dish"] if "盐" in name else DEFAULT_AMOUNTS["sugar_per_dish"]
        if any(k in name for k in ["油", "黄油", "奶油"]):
            return DEFAULT_AMOUNTS["oil_per_dish"]
        if "酱油" in name or "老抽" in name or "生抽" in name:
            return DEFAULT_AMOUNTS["soy_per_dish"]
        if "料酒" in name or "黄酒" in name or "啤酒" in name:
            return DEFAULT_AMOUNTS["wine_per_dish"]
        if any(k in name for k in ["葱", "姜", "蒜", "八角", "花椒", "桂皮", "香叶", "茴香", "五香粉", "十三香", "胡椒粉", "孜然", "辣椒粉", "辣椒", "干辣椒", "尖椒"]):
            return DEFAULT_AMOUNTS["small_aroma_g_per_dish"]
        # 蔬菜类辅料
        if any(k in name for k in ["黑木耳", "木耳", "银耳", "金针菇", "杏鲍菇", "香菇", "平菇", "草菇"]):
            return DEFAULT_AMOUNTS["fungus"]
        return DEFAULT_AMOUNTS["veg_per_dish"]

    # 主料
    if any(k in name for k in ["意大利面", "意面", "蝴蝶面", "螺丝面", "面条", "挂面", "通心粉", "细面条", "米粉"]):
        return DEFAULT_AMOUNTS["pasta"]
    if "鱼" in name or "虾" in name:
        return DEFAULT_AMOUNTS["fish_main"]
    if any(k in name for k in ["五香", "十三", "花椒粉", "辣椒粉"]):
        return DEFAULT_AMOUNTS["small_aroma_g_per_dish"]
    return DEFAULT_AMOUNTS["main_meat"]


def lookup_dish_kcal(name: str) -> tuple:
    """方案 A：菜名查表。返回 (kcal, matched_pattern, source) 或 (None, None, None)。"""
    # 优先匹配长关键词 — 把列表按 pattern 长度降序排
    for pat, kcal, src in sorted(DISH_PATTERNS, key=lambda x: -len(x[0])):
        if re.search(pat, name):
            return kcal, pat, src
    return None, None, None


def reverse_calc_kcal(recipe: dict) -> tuple:
    """方案 B：食材反推。返回 (kcal, source) 或 (None, None)。"""
    servings = max(1, recipe.get("servings", 2))
    ingredients = recipe.get("ingredients", [])
    if not ingredients:
        return None, None

    total_per_dish = 0.0
    matched = 0
    for ing in ingredients:
        nm = ing.get("name", "")
        if not nm:
            continue
        # 查 food energy
        if nm in INGREDIENT_KCAL_PER_100G:
            kcal_per_100 = INGREDIENT_KCAL_PER_100G[nm]
            grams = estimate_grams_for_name(nm, ing.get("isMain", False))
            total_per_dish += kcal_per_100 * grams / 100
            matched += 1

    if matched < 2:
        # 数据太少不可靠
        return None, None

    # 调味糖/油/酱油的总附加
    if any(s in str(ingredients) for s in ["糖", "可乐", "冰糖", "蜂蜜", "甜面酱"]):
        sugar_addition = 60  # 含糖调味额外 +60 kcal/菜
        total_per_dish += sugar_addition

    if any(s in str(ingredients) for s in ["油", "黄油", "奶油", "培根", "芝士", "奶酪"]):
        oil_addition = 30
        total_per_dish += oil_addition

    # cooking loss factor (lock in calories）
    total_per_dish *= 1.10

    per_serving = total_per_dish / servings
    return int(round(per_serving)), f"reverse_calc({matched}项食材)"


def safety_fallback(recipe: dict) -> int:
    """极端兜底：基于 servings 数 + 时长 + 主料极简估算。"""
    servings = max(1, recipe.get("servings", 2))
    duration = recipe.get("duration", 30)
    cuisine = recipe.get("cuisine", "")
    mains = [ing["name"] for ing in recipe.get("ingredients", []) if ing.get("isMain")]
    main = mains[0] if mains else ""

    # 主料为基础估算
    base = 200
    if "鱼" in main:
        base = 180
    elif "肉" in main or "排" in main or "鸡" in main or "鸭" in main:
        base = 280
    elif "牛" in main:
        base = 260
    elif "意" in main or "面" in main:
        base = 350
    elif "豆腐" in main:
        base = 150
    elif "蛋" in main:
        base = 180
    elif "蘑菇" in main or "菇" in main:
        base = 130

    # 时长调整（炖煮类油更多）
    if duration and duration > 60:
        base += 30

    return int(round(base))


def fill_one(recipe: dict, verbose=False) -> dict:
    """尝试填补单条菜谱的 calories 字段。返回 dict 含 result。"""
    name = recipe.get("name", "?")
    if recipe.get("calories", -1) > 0:
        return {"name": name, "method": "skip", "value": recipe["calories"]}

    # A
    kcal_a, pat, src_a = lookup_dish_kcal(name)
    if kcal_a is not None:
        return {"name": name, "method": "A-pattern", "value": kcal_a, "matched": pat, "src": src_a}

    # B
    kcal_b, src_b = reverse_calc_kcal(recipe)
    if kcal_b is not None:
        return {"name": name, "method": "B-reverse", "value": kcal_b, "src": src_b}

    # C
    kcal_c = safety_fallback(recipe)
    return {"name": name, "method": "C-fallback", "value": kcal_c}


def process_all(apply: bool = False, only: str = None):
    results = []
    by_method = Counter()
    by_cuisine = Counter()

    json_files = sorted(ROOT.rglob("*.json"))
    if not json_files:
        print(f"❌ No JSON files found under {ROOT}")
        return

    for path in json_files:
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            print(f"⚠️  skip {path.name}: {e}")
            continue

        if only and data.get("name") != only:
            continue

        if data.get("calories", -1) <= 0:
            res = fill_one(data)
            res["file"] = str(path.relative_to(ROOT.parent.parent))
            res["cuisine"] = data.get("cuisine", "?")
            results.append(res)
            by_method[res["method"]] += 1
            by_cuisine[data.get("cuisine", "?")] += 1

            if apply:
                data["calories"] = res["value"]
                with open(path, "w", encoding="utf-8") as f:
                    json.dump(data, f, ensure_ascii=False, indent=4)

    # 报告
    print(f"\n{'='*60}")
    print(f"📊 处理结果 ({len(results)} 个菜)")
    print(f"{'='*60}")
    print(f"\n按方法分布:")
    for m, n in by_method.most_common():
        pct = 100 * n / max(1, len(results))
        print(f"  {m:15s}  {n:4d}  ({pct:5.1f}%)")
    print(f"\n按菜系分布:")
    for c, n in by_cuisine.most_common():
        print(f"  {c:8s}  {n:4d}")

    if apply:
        print(f"\n✅ 已写入 JSON 文件")
    else:
        print(f"\nℹ️  仅预览，没有 --apply，写入 0 文件")

    # 示例输出前 10 个
    print(f"\n前 10 条样例:")
    for r in results[:10]:
        print(f"  [{r['method']:12s}] {r['value']:4d} kcal | {r['name']} ({r['cuisine']})")

    return results


def write_report(results, path):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["name", "cuisine", "method", "value", "src", "file"])
        for r in results:
            w.writerow([r["name"], r["cuisine"], r["method"], r["value"], r.get("src", ""), r["file"]])
    print(f"\n📄 报告: {path}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="真正写入 JSON")
    ap.add_argument("--only", metavar="NAME", help="只处理单个菜")
    ap.add_argument("--report", metavar="PATH", help="生成 CSV 报告")
    args = ap.parse_args()

    results = process_all(apply=args.apply, only=args.only)
    if results and args.report:
        write_report(results, args.report)
