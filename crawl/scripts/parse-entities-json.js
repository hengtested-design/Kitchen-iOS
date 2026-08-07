#!/usr/bin/env node
/**
 * parse-entities-json.js
 *
 * 解析 CookBook-KG 的 entities_item.json(pro 版,199 道菜) → Recipe JSON。
 *
 * 比 parse-cookbook-kg.js 简单:
 * - 输入是 JSON,不用解 N-triples
 * - 字段结构对齐:主料/辅料/配料/特色/制作步骤
 *
 * 输入: sources/entities_item.json
 * 输出: ../Kitchen/Recipes/<cuisine>/<cuisine>_<slug>.json
 */
'use strict';

const fs = require('fs');
const path = require('path');

// ============================================================
// 路径
// ============================================================
const SOURCE_JSON = path.join(__dirname, '..', 'sources', 'entities_item.json');
const OUTPUT_DIR = path.join(__dirname, '..', '..', 'Kitchen', 'Recipes');

// ============================================================
// 共享工具(从 parse-cookbook-kg.js 复用)
// ============================================================

// 中文量词 → 数字
const CN_NUM = {
    '零': 0, '〇': 0,
    '一': 1, '壹': 1, '幺': 1,
    '二': 2, '贰': 2, '两': 2,
    '三': 3, '叁': 3,
    '四': 4, '肆': 4,
    '五': 5, '伍': 5,
    '六': 6, '陆': 6,
    '七': 7, '柒': 7,
    '八': 8, '捌': 8,
    '九': 9, '玖': 9,
    '十': 10, '拾': 10,
    '半': 0.5,
};

const FUZZY_UNITS = new Set(['适量', '少许', '若干', '随意', '看情况']);

const WEIGHT_TO_GRAM = {
    '斤': 500, '两': 50, '钱': 5,
    '克': 1, 'g': 1, 'G': 1,
    '千克': 1000, '公斤': 1000, 'kg': 1000, 'KG': 1000, 'Kg': 1000,
    '磅': 453, 'lb': 453,
};

const VOLUME_TO_ML = {
    '毫升': 1, 'ml': 1, 'ML': 1, 'mL': 1,
    '升': 1000, 'L': 1000, 'l': 1000,
    '汤匙': 15, '汤勺': 15, '大勺': 15,
    '茶匙': 5, '茶勺': 5, '小勺': 5,
    '杯': 240, '碗': 300, '碟': 100,
    '听': 330, '罐': 330, '瓶': 500,
};

const LENGTH_TO_CM = {
    '厘米': 1, 'cm': 1, '米': 100, 'm': 100,
};

function parseCNNumber(str) {
    if (!str) return null;
    if (str in CN_NUM) return CN_NUM[str];
    if (str.startsWith('十')) {
        const rest = str.slice(1);
        if (!rest) return 10;
        const restNum = CN_NUM[rest];
        if (restNum !== undefined) return 10 + restNum;
        return null;
    }
    const decadeMatch = str.match(/^(.+)十(.*)$/);
    if (decadeMatch) {
        const left = CN_NUM[decadeMatch[1]];
        const right = decadeMatch[2] ? CN_NUM[decadeMatch[2]] : 0;
        if (left !== undefined && right !== undefined) return left * 10 + right;
    }
    return null;
}

function normalize(amount, unit) {
    if (unit in WEIGHT_TO_GRAM) return { amount: amount * WEIGHT_TO_GRAM[unit], unit: '克' };
    if (unit in VOLUME_TO_ML) return { amount: amount * VOLUME_TO_ML[unit], unit: '毫升' };
    if (unit in LENGTH_TO_CM) return { amount: amount * LENGTH_TO_CM[unit], unit: '厘米' };
    return { amount, unit };
}

function parseAmount(unit) {
    if (!unit) return { amount: 0, unit: '' };
    const original = unit.trim();

    if (FUZZY_UNITS.has(original)) return { amount: 0, unit: original };

    // 分数
    let m = original.match(/^(\d+)\/(\d+)([a-zA-Z\u4e00-\u9fff]+)$/);
    if (m) return normalize(parseInt(m[1], 10) / parseInt(m[2], 10), m[3]);

    // 范围
    m = original.match(/^(\d+(?:\.\d+)?)[-~](\d+(?:\.\d+)?)([a-zA-Z\u4e00-\u9fff]+)$/);
    if (m) return normalize((parseFloat(m[1]) + parseFloat(m[2])) / 2, m[3]);

    // 阿拉伯数字 + 单位
    m = original.match(/^(\d+(?:\.\d+)?)([a-zA-Z\u4e00-\u9fff]+)$/);
    if (m) return normalize(parseFloat(m[1]), m[2]);

    // 中文数字 + 单位
    const cnMatch = original.match(/^([零〇一壹幺二贰两三叁四肆五伍六陆七柒八捌九玖拾十半]+)(.+)$/);
    if (cnMatch) {
        const num = parseCNNumber(cnMatch[1]);
        if (num !== null) return normalize(num, cnMatch[2]);
    }

    // "几X" → 模糊
    if (original.startsWith('几')) return { amount: 0, unit: original.slice(1) };

    // "大/小/小半/大半X" → 模糊
    if (/^(大|小|小半|大半)/.test(original)) return { amount: 0, unit: original };

    return { amount: 0, unit: original };
}

function slugifyChinese(name) {
    return name
        .trim()
        .replace(/[a-zA-Z]+/g, m => m.toLowerCase())
        .replace(/\s+/g, '_')
        .replace(/[^\u4e00-\u9fa5a-z0-9_]/g, '')
        .replace(/_+/g, '_')
        .replace(/^_|_$/g, '');
}

// ============================================================
// 领域字段
// ============================================================
const DIFFICULTY_MAP = {
    '简单': 1, '普通': 2, '高级': 4,
};

const DURATION_MAP = {
    '十分钟': 10, '二十分钟': 20, '廿分钟': 20,
    '半小时': 30, '三刻钟': 45,
    '一小时': 60, '数小时': 180, '一天': 1440,
};

function guessCuisine(name, method) {
    const n = name.toLowerCase();
    const m = method || '';

    if (/(水煮|鱼香|宫保|麻婆|回锅|酸菜鱼|辣子鸡|夫妻肺片|川味|川)/.test(n)) return '川菜';
    if (n.includes('麻辣') || m === '麻辣') return '川菜';

    if (/(白切|清蒸|烧鹅|蜜汁|煲仔|肠粉|早茶|叉烧|广式|粤)/.test(n)) return '粤菜';

    if (/(东坡|西湖|龙井|宋嫂|叫花|糖醋|杭|浙)/.test(n)) return '浙菜';

    if (/(剁椒|湘|腊味|口味虾|臭豆腐)/.test(n)) return '湘菜';

    if (/(糖醋鲤鱼|九转|葱烧|油爆|鲁)/.test(n)) return '鲁菜';

    if (/(意面|意粉|意大利|披萨|牛排|汉堡|沙拉|奶油|培根|黑椒|茄汁|海鲜|番茄|蕃茄|酥)/.test(n)) return '西餐';

    if (n.includes('凉拌')) return '凉菜';

    return '家常菜';
}

// ============================================================
// 解析一条食材
// 输入: "五花肉: 800克" → { name, amount, unit, isMain }
// ============================================================
function parseIngredient(raw, isMain) {
    const m = raw.match(/^([^:]+):\s*(.+)$/);
    if (!m) return null;
    const name = m[1].trim();
    const unitRaw = m[2].trim();
    const { amount, unit } = parseAmount(unitRaw);
    return { name, amount, unit, isMain };
}

// ============================================================
// 解析一步
// 输入: "1: 准备食材。" → { number: 1, description: "准备食材。" }
// ============================================================
function parseStep(raw, idx) {
    const m = raw.match(/^\d+[\.\:、\)]?\s*(.+)$/);
    const description = m ? m[1].trim() : raw.trim();
    return { number: idx + 1, description };
}

// ============================================================
// 解析特色字段
// 格式: "口味: 咸甜", "工艺: 炖", "耗时: 一小时", "难度: 简单"
// ============================================================
function parseFeatures(features) {
    const out = { tags: [], duration: 30, difficulty: 2, method: '' };
    for (const f of features || []) {
        if (f.startsWith('口味:')) {
            out.tags.push(f.slice(3).trim());
        } else if (f.startsWith('工艺:')) {
            out.method = f.slice(3).trim();
            out.tags.push(out.method);
        } else if (f.startsWith('耗时:')) {
            const dur = f.slice(3).trim();
            out.duration = DURATION_MAP[dur] || 30;
        } else if (f.startsWith('难度:')) {
            const d = f.slice(3).trim();
            out.difficulty = DIFFICULTY_MAP[d] || 2;
        }
    }
    return out;
}

// ============================================================
// 解析单道菜
// ============================================================
function parseDish(name, info, id) {
    if (!info || typeof info !== 'object') return null;

    // 过滤非菜条目
    // 知识图谱里有些实体的名字是节点名,不是菜:
    // - "五花肉(菜品)" - 食材实体
    // - "意大利面(菜品)" - 食材实体
    // - "详解片鱼步骤" - 教程标题
    if (/[(\uff08]菜品[)\uff09]/.test(name)) return null;
    if (/详解|步骤|教程|做法/.test(name)) return null;
    // 没有主料/辅料的也算非菜
    if (!info['主料'] && !info['辅料']) return null;
    // 步骤是空的也不算菜 (数据源残缺)
    if (!info['制作步骤'] || info['制作步骤'].length === 0) return null;

    const features = parseFeatures(info['特色'] || []);

    const ingredients = [];
    const seen = new Set();

    // 主料
    for (const raw of info['主料'] || []) {
        const ing = parseIngredient(raw, true);
        if (ing && !seen.has(ing.name)) {
            ingredients.push(ing);
            seen.add(ing.name);
        }
    }
    // 辅料
    for (const raw of info['辅料'] || []) {
        const ing = parseIngredient(raw, false);
        if (ing && !seen.has(ing.name)) {
            ingredients.push(ing);
            seen.add(ing.name);
        }
    }
    // 配料
    for (const raw of info['配料'] || []) {
        const ing = parseIngredient(raw, false);
        if (ing && !seen.has(ing.name)) {
            ingredients.push(ing);
            seen.add(ing.name);
        }
    }

    // 步骤
    const steps = (info['制作步骤'] || []).map((s, idx) => parseStep(s, idx));

    const cuisine = guessCuisine(name, features.method);

    return {
        id,
        name,
        cuisine,
        cover: '',
        calories: 0,
        difficulty: features.difficulty,
        duration: features.duration,
        servings: 2,
        tags: features.tags,
        ingredients,
        steps,
        tips: undefined,
        // 标记爬虫来源,用于增量同步时只清自己生成的文件
        _source: 'cookbook-kg',
    };
}

// ============================================================
// 增量同步写入
// 策略: 先清除之前 crawler 生成的文件(带 _source 标记),
//      然后再写入新菜。这是安全的: App 里手写的菜不带 _source,不会被清。
// ============================================================
function writeRecipesIncremental(recipes) {
    // 1. 计算本次要写的菜的文件名
    const desired = new Set();
    const byCuisine = {};
    for (const r of recipes) {
        if (!byCuisine[r.cuisine]) byCuisine[r.cuisine] = [];
        byCuisine[r.cuisine].push(r);
        const slug = slugifyChinese(r.name);
        desired.add(path.join(r.cuisine, `${r.cuisine}_${slug}.json`));
    }

    // 2. 扫描现有 Recipes,清掉带 _source 标记且不在 desired 集里的
    let deleted = 0;
    if (fs.existsSync(OUTPUT_DIR)) {
        for (const cuisine of fs.readdirSync(OUTPUT_DIR)) {
            const cuisineDir = path.join(OUTPUT_DIR, cuisine);
            if (!fs.statSync(cuisineDir).isDirectory()) continue;
            for (const filename of fs.readdirSync(cuisineDir)) {
                if (!filename.endsWith('.json')) continue;
                const relPath = path.join(cuisine, filename);
                if (desired.has(relPath)) continue;  // 本次要写,留着
                // 检查是否带 _source 标记
                const fullPath = path.join(cuisineDir, filename);
                try {
                    const content = JSON.parse(fs.readFileSync(fullPath, 'utf-8'));
                    if (content._source) {
                        fs.unlinkSync(fullPath);
                        deleted++;
                    }
                } catch (e) {
                    // 读不动就跳过，不破其他文件
                }
            }
        }
    }

    // 3. 写入新菜
    let written = 0;
    for (const [cuisine, items] of Object.entries(byCuisine)) {
        const cuisineDir = path.join(OUTPUT_DIR, cuisine);
        if (!fs.existsSync(cuisineDir)) {
            fs.mkdirSync(cuisineDir, { recursive: true });
        }

        for (const r of items) {
            const slug = slugifyChinese(r.name);
            const filename = `${cuisine}_${slug}.json`;
            const target = path.join(cuisineDir, filename);
            const tmp = target + '.tmp';
            fs.writeFileSync(tmp, JSON.stringify(r, null, 2), 'utf-8');
            fs.renameSync(tmp, target);
            written++;
        }
    }

    return { written, deleted, cuisines: Object.keys(byCuisine) };
}

// ============================================================
// 入口
// ============================================================
function main() {
    console.log('📖 读取 JSON:', SOURCE_JSON);

    const raw = fs.readFileSync(SOURCE_JSON, 'utf-8');
    console.log(`   大小: ${(raw.length / 1024).toFixed(1)} KB`);

    const data = JSON.parse(raw);
    const names = Object.keys(data);
    console.log(`   菜数: ${names.length}`);

    // 解析每道菜(遇到非菜条目跳过)
    const recipes = [];
    let skipped = 0;
    // ID 从 10000 开始,避免跟手写菜(1-15)冲突
    const ID_OFFSET = 10000;
    names.forEach((name, idx) => {
        const r = parseDish(name, data[name], idx + ID_OFFSET);
        if (r) recipes.push(r);
        else skipped++;
    });

    // 按菜系分组
    const byCuisine = {};
    for (const r of recipes) {
        byCuisine[r.cuisine] = (byCuisine[r.cuisine] || 0) + 1;
    }
    console.log('\n📊 菜系分布:');
    for (const [c, n] of Object.entries(byCuisine).sort((a, b) => b[1] - a[1])) {
        console.log(`   ${c}: ${n} 道`);
    }
    if (skipped) console.log(`   跳过 ${skipped} 个非菜条目`);

    console.log('\n💾 写入(增量):', OUTPUT_DIR);
    const { written, deleted, cuisines } = writeRecipesIncremental(recipes);

    console.log(`\n✅ 完成!写了 ${written} 个 JSON 文件,清理 ${deleted} 个过期文件`);
    console.log(`💡 增量同步:清理 crawler 生成的旧菜,保留手写菜(不带 _source 标记)`);
}

main();
