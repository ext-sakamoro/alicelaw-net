# Skill Application Plan (alicelaw-net)

業界一般の Web ベストプラクティス Skill 群 (~/claude-config/claude-skills/) を本プロジェクトに段階導入する計画

## 現状サマリ

- 言語 / 構成: 静的 HTML + 生 JS (`alice-kernel.js` 403 行) + GLSL + Cloudflare Pages Functions
- 既存 CI / lint / test: いずれもなし
- 現状違反 (baseline): `alice-kernel.js` で var 131 / console.log 1 件

## 段階導入プラン

### Phase 1: package.json + ESLint 導入 (推奨優先)

- `package.json.example` → `package.json` にリネーム
- `eslint.config.js.example` → `eslint.config.js` にリネーム
- `.prettierrc.example` → `.prettierrc` にリネーム
- `npm install` で devDependencies 取得
- 既存 `alice-kernel.js` の 131 var → let / const 自動変換 (codemod)
- console.log 1 件削除
- 関連 Skill: [eslint-flat-config], [ts-strict-config] (の JS 適用版)

### Phase 2: CI 統合

- `.github/workflows/ci-unified.yml.example` → `.github/workflows/ci.yml`
- lint / format / link-check の 3 job 並列
- 関連 Skill: [web-ci-parallel]

### Phase 3: テスト (任意)

- WebGL2 + GLSL を含むため jsdom テスト困難、Playwright で実 Chrome 推奨
- Cloudflare Pages Functions (`functions/[card].js`) は Vitest + miniflare で可能
- 関連 Skill: [web-three-layer-testing]

### Phase 4: i18n (将来)

- 現状日本語のみ、英語版があれば [i18next-pattern] 適用余地

## 注意

- 既存挙動を破壊しないよう、リネーム時は各 PR で 1 ファイルずつ
- WebGL シェーダー / SDF / Cloudflare Worker は jsdom で動かない、E2E は実環境必須

## 関連 Skill (~/claude-config/claude-skills/)

- eslint-flat-config
- web-ci-parallel
- ts-strict-config (JS 適用版)
- web-three-layer-testing
