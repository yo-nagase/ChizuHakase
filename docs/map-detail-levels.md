# 拡大時の地図詳細化

日本の平面地図、世界の平面地図・地球儀は、拡大率3倍以上で `detailedRings` に切り替える。
基準は `GameRules.mapDetailZoom`。平面地図は `ZoomPan` の操作中の倍率から
詳細度だけを環境値で渡すため、ピンチや長押しスライドを離す前にも切り替わる。

- 通常の `rings`、表示範囲、ラベル位置、ステージ構成、インセット位置は変更しない。
- 描画・当たり判定・VoiceOverは同じ選択済み形状を使う。
- 詳細形状が通常のbboxを少し超える場合、当たり判定のbboxだけ広げる。フィット用の枠は元のまま。
- 周辺の収録国・都道府県のグレー表示も詳細化する。収録外の背景地形は軽量な通常データを使う。
- 詳細データの無い旧ファイルや、不正な詳細リングは通常の輪郭へフォールバックする。
- 別の島を追加せず、既存の島・穴に対応する高密度のリングだけ採用する。
  同じ元データをmapshaperで一括簡略化し、共有する県境・国境のつながりを保持する。
- 世界のインセット国は、既存の1:10mソースの間引き前のリングを使う。
  元データに無い海岸線の細部は増やせない（シンガポールは38点→40点）。

## 再生成

リポジトリ直下で実行。既存の通常用GeoJSONと同じ版の元データを使うこと。
`--details` を省略すると従来の通常用のみを生成するので、出荷用には下記を使う。

```sh
npx --yes mapshaper@0.6.113 tools/japan.geojson \
  -simplify visvalingam 40% keep-shapes -clean \
  -o /tmp/japan_detail.geojson format=geojson
python3 tools/build_map_data.py --details /tmp/japan_detail.geojson \
  --output ChizuHakase/Resources/PrefectureShapes.json

npx --yes mapshaper@0.6.113 tools/ne_10m_countries.geojson \
  -simplify visvalingam 16% keep-shapes -clean \
  -o /tmp/world_detail.geojson format=geojson
python3 tools/build_world_map_data.py --details /tmp/world_detail.geojson \
  --output ChizuHakase/Resources/WorldShapes.json
python3 tools/validate_world_data.py
python3 -m unittest discover -s tools -p 'test_map_detail.py'
```

通常用の全フィールドが変更前と一致することを確認済み。日本の詳細座標は
正規化幅1000に対して小数3桁、世界は既存と同じ経緯度の小数4桁。
アプリはビルド時や実行時にダウンロード・再生成しない。

## 規模と検証

| | 通常の点数 | 詳細の点数 | 通常＋詳細のJSON |
| --- | ---: | ---: | ---: |
| 日本 | 7,645 | 26,997 | 577 KiB |
| 世界の収録国 | 22,643 | 75,687 | 背景込み1,869 KiB |

バンドル増分は合計約1.8 MiB。世界の容量検査は通常データ600 KiBの予算を維持し、
詳細データだけ別に1,600 KiB（実測約1,366 KiB）を設ける。

ローカルMacの最適化ビルドで実際の `GlobeGeometry.path` を使い、
全167か国を100方向に投影・パス生成したCPU時間は、通常中央値1.52ms、
詳細中央値4.69ms / p95 5.08ms。SwiftUIの描画や実機のフレームレートは含まない。
古いiPhoneでの高倍率ドラッグの滑らかさは別途実機確認が必要。

テストは実データの読込、通常時の形状維持、詳細化しても変わらない表示範囲、
詳細化で追加された岬への直接タップ、通常・詳細両方での基準点、
地球儀の詳細形状のタップ、不正データのフォールバック、ピンチ後のリセットを確認する。
