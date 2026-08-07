#!/usr/bin/env node
/**
 * parse-cookbook-kg.js
 *
 * 把 CookBook-KG 的 N-triples 文件解析成我们的 Recipe JSON Schema。
 * 增量同步:只覆盖 crawler 自己生成的文件,不动 App 内手写的 15 道菜。
 *
 * 输入: sources/aifoodtime.nt
 * 输出: ../Kitchen/Recipes/<cuisine>/<cuisine>_<slug>.json
 *
 * 当前数据源: https://github.com/ngl567/CookBook-KG
 * 数据规模: 50 道菜(10 个菜系列 × 5 变体)
 */
'use strict';

const fs = require('fs');
const path = require('path');

// ============================================================
// 路径配置
// ============================================================
const SOURCE_NT = path.join(__dirname, '..', 'sources', 'aifoodtime.nt');
const OUTPUT_DIR = path.join(__dirname, '..', '..', 'Kitchen', 'Recipes');

// ============================================================
// 中文量词 → 数字
// ============================================================
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
    '半': 0.5, '半': 0.5,
};

// 模糊量词(留 amount=0,只显示 unit)
const FUZZY_UNITS = new Set(['适量', '少许', '若干', '随意', '看情况']);

// 重量单位换算
const WEIGHT_TO_GRAM = {
    '斤': 500,    // 1 斤 = 500 g
    '两': 50,     // 1 两 = 50 g
    '钱': 5,      // 1 钱 = 5 g
    '克': 1, 'g': 1, 'G': 1,
    '千克': 1000, '公斤': 1000, 'kg': 1000, 'KG': 1000, 'Kg': 1000,
    '磅': 453, 'lb': 453,
};

// 体积单位换算
const VOLUME_TO_ML = {
    '毫升': 1, 'ml': 1, 'ML': 1, 'mL': 1,
    '升': 1000, 'L': 1000, 'l': 1000,
    '汤匙': 15, '汤勺': 15, '大勺': 15,
    '茶匙': 5, '茶勺': 5, '小勺': 5,
    '杯': 240, '碗': 300, '碟': 100,
    '听': 330, '罐': 330, '瓶': 500,
};

// 长度单位
const LENGTH_TO_CM = {
    '厘米': 1, 'cm': 1, '米': 100, 'm': 100,
};

// ============================================================
// 把中文数字 + 量词解析成 { amount, unit }
// 例如: "200克" → { amount: 200, unit: "克" }
//       "1勺" → { amount: 1, unit: "勺" }
//       "一斤" → { amount: 500, unit: "克" }
//       "适量" → { amount: 0, unit: "适量" }
//       "半只" → { amount: 0.5, unit: "只" }
//       "几片" → { amount: 0, unit: "片" }  // 模糊量词
//       "1/2勺" → { amount: 0.5, unit: "勺" }
//       "2-3汤匙" → { amount: 2.5, unit: "汤匙" }
//       "1/3个" → { amount: 0.33, unit: "个" }
// ============================================================
function parseAmount(unit) {
    if (!unit) return { amount: 0, unit: '' };
    const original = unit.trim();

    // 模糊量词
    if (FUZZY_UNITS.has(original)) {
        return { amount: 0, unit: original };
    }

    // 1) 分数: "1/2勺", "2/3汤勺", "1/3个"
    let m = original.match(/^(\d+)\/(\d+)([a-zA-Z\u4e00-\u9fff]+)$/);
    if (m) {
        const num = parseInt(m[1], 10) / parseInt(m[2], 10);
        const u = m[3];
        return normalize(num, u);
    }

    // 2) 范围: "2-3汤匙" → 取中间值
    m = original.match(/^(\d+(?:\.\d+)?)[-~](\d+(?:\.\d+)?)([a-zA-Z\u4e00-\u9fff]+)$/);
    if (m) {
        const lo = parseFloat(m[1]);
        const hi = parseFloat(m[2]);
        const u = m[3];
        return normalize((lo + hi) / 2, u);
    }

    // 3) 纯数字 + 单位: "200克", "3个", "1.5勺"
    m = original.match(/^(\d+(?:\.\d+)?)([a-zA-Z\u4e00-\u9fff]+)$/);
    if (m) {
        const num = parseFloat(m[1]);
        const u = m[2];
        return normalize(num, u);
    }

    // 4) 中文数字 + 单位: "一斤", "三片", "半个"
    const cnMatch = original.match(/^([零〇一壹幺二贰两三叁四肆五伍六陆七柒八捌九玖拾十半]+)(.+)$/);
    if (cnMatch) {
        const numStr = cnMatch[1];
        const u = cnMatch[2];
        const num = parseCNNumber(numStr);
        if (num !== null) {
            return normalize(num, u);
        }
    }

    // 5) "几X" → 模糊量词
    if (original.startsWith('几')) {
        return { amount: 0, unit: original.slice(1) };
    }

    // 6) "大半X" / "一小X" → 模糊
    if (/^(大|小|小半|大半)/.test(original)) {
        return { amount: 0, unit: original };
    }

    // 7) 兜底:解析不动,amount=0
    return { amount: 0, unit: original };
}

// 中文数字字符串 → 数字
function parseCNNumber(str) {
    if (!str) return null;
    if (str in CN_NUM) return CN_NUM[str];

    // "十X" → 10 + X
    if (str.startsWith('十')) {
        const rest = str.slice(1);
        if (!rest) return 10;
        const restNum = CN_NUM[rest];
        if (restNum !== undefined) return 10 + restNum;
        return null;
    }

    // "X十" → X*10
    // "X十Y" → X*10 + Y
    const decadeMatch = str.match(/^(.+)十(.*)$/);
    if (decadeMatch) {
        const left = CN_NUM[decadeMatch[1]];
        const right = decadeMatch[2] ? CN_NUM[decadeMatch[2]] : 0;
        if (left !== undefined && right !== undefined) {
            return left * 10 + right;
        }
    }

    return null;
}

// 标准化:识别单位换算
function normalize(amount, unit) {
    // 重量换算
    if (unit in WEIGHT_TO_GRAM) {
        return { amount: amount * WEIGHT_TO_GRAM[unit], unit: '克' };
    }
    // 体积换算
    if (unit in VOLUME_TO_ML) {
        return { amount: amount * VOLUME_TO_ML[unit], unit: '毫升' };
    }
    // 长度换算
    if (unit in LENGTH_TO_CM) {
        return { amount: amount * LENGTH_TO_CM[unit], unit: '厘米' };
    }
    // 兜底
    return { amount, unit };
}

// ============================================================
// 工具:中文 slug 化
// ============================================================
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
// 字段映射:难度(中文 → 1-5)
// ============================================================
const DIFFICULTY_MAP = {
    '简单': 1,
    '普通': 2,
    '高级': 4,
};

// ============================================================
// 字段映射:耗时(中文 → 分钟数)
// ============================================================
const DURATION_MAP = {
    '十分钟': 10,
    '二十分钟': 20,
    '半小时': 30,
    '三刻钟': 45,
    '一小时': 60,
    '数小时': 180,
    '一天': 1440,
};

// ============================================================
// 菜系归类启发式
// ============================================================
function guessCuisine(name, method) {
    const n = name.toLowerCase();
    const m = method || '';

    if (/(水煮|鱼香|宫保|麻婆|回锅|酸菜鱼|辣子鸡|夫妻肺片)/.test(n)) return '川菜';
    if (n.includes('麻辣') || m === '麻辣') return '川菜';

    if (/(白切|清蒸|烧鹅|蜜汁|煲仔|肠粉|早茶|叉烧)/.test(n)) return '粤菜';

    if (/(东坡|西湖|龙井|宋嫂|叫花|糖醋|西湖醋鱼)/.test(n)) return '浙菜';

    if (/(剁椒|辣椒|湘|腊味|口味虾|臭豆腐)/.test(n)) return '湘菜';

    if (/(糖醋鲤鱼|九转|葱烧|油爆)/.test(n)) return '鲁菜';

    if (/(意面|披萨|牛排|汉堡|沙拉|意大利)/.test(n)) return '西餐';

    if (n.includes('凉拌')) return '凉菜';

    return '家常菜';
}

// ============================================================
// 解析食材列表(主料/辅料/配料)
// ============================================================
function parseIngredientLists(zhuliao, fuliia, peiliao) {
    const items = [];
    const seen = new Set();

    function process(raw, isMain) {
        const m = raw.match(/^([^:]+):\s*(.+)$/);
        if (!m) return;
        const name = m[1].trim();
        const unitRaw = m[2].trim();
        if (seen.has(name)) return;
        seen.add(name);

        const { amount, unit } = parseAmount(unitRaw);
        items.push({
            name: name,
            amount: amount,
            unit: unit,
            isMain: isMain,
        });
    }

    for (const raw of zhuliao || []) process(raw, true);
    for (const raw of fuliia || []) process(raw, false);
    for (const raw of peiliao || []) process(raw, false);

    return items;
}

// ============================================================
// 解析步骤
// ============================================================
function parseSteps(rawText) {
    if (!rawText) return [];
    const parts = rawText.split(/\s*\d+[\.\:、\)]/).filter(s => s.trim());
    return parts.map((desc, idx) => ({
        number: idx + 1,
        description: desc.trim(),
    }));
}

// ============================================================
// 解析特色
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
// 主函数:解析 N-triples
// ============================================================
function parseNTriples(text) {
    const subjectMap = {};
    const lineRe = /<([^>]+)> <([^>]+)> (.*?) \.\s*$/;

    for (const line of text.split('\n')) {
        if (!line.trim()) continue;
        const m = line.match(lineRe);
        if (!m) continue;

        const subject = m[1];
        const predicate = m[2];
        let object = m[3].trim();
        const localName = predicate.split('/').pop();

        if (object.startsWith('"') && object.endsWith('"')) {
            object = object.slice(1, -1);
        }

        if (!subjectMap[subject]) subjectMap[subject] = {};
        if (!subjectMap[subject][localName]) subjectMap[subject][localName] = [];
        subjectMap[subject][localName].push(object);
    }

    const dishes = [];
    for (const [subj, props] of Object.entries(subjectMap)) {
        const hasName = props['名称'] && props['名称'].length > 0;
        const hasContent = (props['主料'] || props['辅料'] || props['制作步骤'] || []).length > 0;
        if (hasName && hasContent) {
            const idMatch = subj.match(/\/(\d+)$/);
            const id = idMatch ? parseInt(idMatch[1], 10) : 0;
            const name = props['名称'][0];
            const features = parseFeatures(props['特色'] || []);
            const cuisine = guessCuisine(name, features.method);
            const ingredients = parseIngredientLists(
                props['主料'],
                props['辅料'],
                props['配料'],
            );
            const steps = parseSteps((props['制作步骤'] || [])[0] || '');

            dishes.push({
                id: id,
                name: name,
                cuisine: cuisine,
                cover: '',
                calories: 0,
                difficulty: features.difficulty,
                duration: features.duration,
                servings: 2,
                tags: features.tags,
                ingredients: ingredients,
                steps: steps,
                tips: undefined,
            });
        }
    }

    return dishes;
}

// ============================================================
// 增量同步:只覆盖 crawler 自己的输出,不删其他文件
// 旧的覆盖菜(用 N-triples ID 标记)走"_v2.json"临时,再原子重命名
// ============================================================
function writeRecipesIncremental(recipes) {
    // 按菜系分组
    const byCuisine = {};
    for (const r of recipes) {
        if (!byCuisine[r.cuisine]) byCuisine[r.cuisine] = [];
        byCuisine[r.cuisine].push(r);
    }

    let written = 0;
    let skipped = 0;

    for (const [cuisine, items] of Object.entries(byCuisine)) {
        const cuisineDir = path.join(OUTPUT_DIR, cuisine);
        if (!fs.existsSync(cuisineDir)) {
            fs.mkdirSync(cuisineDir, { recursive: true });
        }

        for (const r of items) {
            const slug = slugifyChinese(r.name);
            const filename = `${cuisine}_${slug}.json`;
            const target = path.join(cuisineDir, filename);

            // 临时文件 → 原子重命名(避免半截写入)
            const tmp = target + '.tmp';
            fs.writeFileSync(tmp, JSON.stringify(r, null, 2), 'utf-8');
            fs.renameSync(tmp, target);
            written++;
        }
    }

    return { written, skipped, cuisines: Object.keys(byCuisine) };
}

// ============================================================
// 入口
// ============================================================
function main() {
    console.log('📖 读取 N-triples:', SOURCE_NT);
    const text = fs.readFileSync(SOURCE_NT, 'utf-8');
    console.log(`   大小: ${(text.length / 1024).toFixed(1)} KB`);

    console.log('\n🔄 解析中...');
    const recipes = parseNTriples(text);
    console.log(`   解析到 ${recipes.length} 道菜`);

    const byCuisine = {};
    for (const r of recipes) {
        byCuisine[r.cuisine] = (byCuisine[r.cuisine] || 0) + 1;
    }
    console.log('\n📊 菜系分布:');
    for (const [c, n] of Object.entries(byCuisine).sort((a, b) => b[1] - a[1])) {
        console.log(`   ${c}: ${n} 道`);
    }

    console.log('\n💾 写入(增量):', OUTPUT_DIR);
    const { written, cuisines } = writeRecipesIncremental(recipes);

    console.log(`\n✅ 完成!写了 ${written} 个 JSON 文件,覆盖 ${cuisines.length} 个菜系`);
    console.log('\n💡 增量同步:只覆盖 crawler 自己生成的文件,保留手写菜');
}

main();
