# Kitchen Crawler

把外部菜谱数据源转成 App 用的 JSON Schema。

## 架构

```
crawl/
├── sources/                     # 原始数据(离线)
│   └── aifoodtime.nt          # CookBook-KG N-triples
├── scripts/                     # 解析器
│   └── parse-cookbook-kg.js   # NT → Recipe JSON
├── output/                      # (暂未使用,直接输出到 Recipes/)
└── package.json
```

输出位置: `../Kitchen/Recipes/<cuisine>/<cuisine>_<slug>.json`

## 当前数据源

**CookBook-KG** (https://github.com/ngl567/CookBook-KG)
- ⭐ 400 stars
- 50 道菜(10 个菜系列 × 5 变体)
- 中文,字段完整(主料/辅料/步骤/难度/时长)
- 缺点:没图片、没热量、食材用量是中文量词

## 快速用

```bash
# 同步全部 50 道菜
npm run sync

# 以后增加新数据源:
# 1. 在 sources/ 放原始数据
# 2. 在 scripts/ 加新解析器
# 3. 处理逻辑放在脚本里
```

## 添加新数据源

1. 在 `sources/` 放原始数据
2. 在 `scripts/` 加新解析器,例如 `parse-meishijie.js`
3. **不要在 App 那边改**,那边只读 JSON,不关心来源

## Schema 字段

```json
{
  "id": 1,
  "name": "鱼香肉丝",
  "cuisine": "川菜",      // 用于菜系筛选
  "cover": "",             // 封面图 URL,可空
  "calories": 0,           // 千卡,可空
  "difficulty": 1,         // 1-5
  "duration": 20,          // 分钟
  "servings": 2,           // 份量
  "tags": ["鱼香", "炒"],
  "ingredients": [
    { "name": "猪里脊", "amount": 0, "unit": "300克", "isMain": true },
    { "name": "糖", "amount": 0, "unit": "适量", "isMain": false }
  ],
  "steps": [
    { "number": 1, "description": "准备食材。", "tips": null }
  ],
  "tips": null
}
```

## 已知缺失

- `cover`:CookBook-KG 没图片,需要替换源
- `calories`:数据源没热量,需要补充
- `amount`:CookBook-KG 用中文量词,留 0 时直接显示 unit
