## 地・白ぎつねの立体カード（2026-09-22）

案⑤を採用。組み込みImageGenで背景と透過キャラクターを分離し、`phantom-earth-forest` と `phantom-earth-fox` に保存。
EarthHolographicCardFaceで背景・白ぎつね・光粒を異なる距離で動かす視差表現を使用。背景には190個の金色・白・ミント・薄紫の箔粒と星形の光を重ね、傾きで明るさが変わる。白ぎつねより後ろに描き、顔を隠さない。金属枠と「地」はSwiftUIで描画し、サンプル番号は表示しない。Reduce Motionでは視差と動く虹色反射を止める。取得条件は変更なし。
編集プロンプト：背景は「Remove the entire fox, tail, paws, jewelry, border, title and number; fill with matching forest landscape」。前景は「Extract only the complete fox, tail and jewelry on genuine transparent alpha, preserve original pose and canvas alignment」。

# まぼろしカード・イラスト（2026-09-21）

天は承認済みの白銀の子龍（初回案②）を使用。サンプル番号だけをImageGenで除去し、1536pxのJPEGへ変換。絵に含まれる「天」とメタル枠をそのまま表示し、SwiftUIで傾きに追従する虹色の反射・光沢・厚みの影を重ねる。Reduce Motionでは動く箔を停止。一覧と詳細は同じSkyHolographicCardFaceを使用。
海と世界7種は専用風景画・金箔の縁・カード内の名前で描画。地は上記の白ぎつねの立体カードを使用。
日本全国カードはデザインを作り直すため、現在は白い無地のカードを表示する。地図・文字・星空・ホログラム・金属の縁は表示しない。旧日本用JPEGは保管素材であり、現在のカードには使用しない。
風景画は各地域をイメージした創作であり、実在地点の写真や地図ではない。
未入手時には風景・地図・名前を表示しない。

素材は組み込み ImageGen で1種類ずつ生成。アプリ用に長辺1200pxのJPEG（品質88）へ変換。
保存先：`ChizuHakase/Resources/Assets.xcassets/PhantomArt/phantom-art-{key}.imageset/art.jpg`
11枚合計約5.2MiB。天・日本以外のカードの文字・縁・番号・箔はSwiftUIで重ねる。

## 使用プロンプト

各画像の入力は以下の共通文に、その画像の個別文を連結したもの。

### 共通文

Create a finished illustration asset for a premium collectible geography card in a Japanese children's exploration game. Portrait 2:3 canvas, edge-to-edge artwork only. Exquisite hand-painted animated feature background art, richly detailed miniature-world atmosphere, strong readable composition, luminous jewel colors, warm painterly light, tactile gouache textures, enchanting but geographically grounded, refined and beautiful enough to collect. NOT a UI mockup. NO text, lettering, numbers, border, frame, card outline, logos, icons or watermark. Main subject fills central 75%; keep bottom 18% relatively dark and quiet to support a title added by code. Avoid stock gradients, neon rings, generic space backgrounds, flat vector icons, photographic realism. Consistent cohesive art direction across a series. 

### sky

Eastern Japan at dawn. Majestic snow-capped Mount Fuji seen beyond layered indigo mountain ridges, glowing coral and golden sunrise, immense sculptural peach clouds lit from within, tiny flying cranes for scale, gold dust in sunlight. Heroic serene upward movement, palette coral rose, ultramarine and pale gold.

### earth

Central Japan's mountain heart. Towering emerald and turquoise Japanese alpine peaks, waterfall threading down rock into a sapphire river, ancient cedar forest, cloud shadows and brilliant sun shafts. A luminous mountain valley diorama, strong monumental shapes. Palette jade green, deep teal, amber gold.

### sea

Western Japan's inland sea. A sweeping luminous cobalt and turquoise sea with several lush small Japanese islands, white swirling tidal currents, a tiny elegant sailboat, luminous cumulus clouds, golden sunlight on water, coral-red accent in foreground foliage. Dramatic curved composition. Palette ocean blue, aquamarine, pearl, soft gold.

### north-america

North America: an immense turquoise glacial lake beneath dramatic Canadian Rocky Mountain peaks, dense pine forests, a bald eagle flying overhead, distant northern lights softly visible in a twilight sky. Warm gold reflections contrast deep forest teal. No buildings.

### south-america

South America: a sweeping Amazon rainforest river leading toward distant dramatic Andean peaks, a brilliant scarlet macaw flying across the upper right, broad tropical leaves, luminous golden dawn mist, tiny cascading waterfalls. Palette emerald, warm coral red and golden yellow.

### europe

Europe: an enchanting hilltop stone castle and ancient village beside a sapphire alpine lake, snow-capped Alps rising in the background, cypress and flower-filled meadows in foreground, morning mist glowing lavender and amber. Beautiful expansive layered landscape.

### africa

Africa: golden savanna at sunset, sculptural umbrella acacia tree, a graceful giraffe and elephant family small in the midground, mighty waterfalls and a distant mountain on horizon, luminous amber sky with dramatic rose clouds. A vast living landscape, no caricatures, no human figures.

### asia

Asia: monumental Himalayan snow peaks high above a luminous jade river winding through forested Asian mountains, elegant traditional East Asian pagoda small on one rocky ridge, pink flowering branches in foreground, golden clouds, peaceful majestic expanse. Rich indigo, jade, crimson and honey gold.

### oceania

Oceania: extraordinary tropical Pacific island lagoon with emerald volcanic peaks, curved palm trees, coral reefs visible beneath crystal turquoise shallows, one sea turtle swimming in foreground, sunlit white clouds, distant tiny islands. Palette turquoise, coral peach, jade, ultramarine.

### antarctica

Antarctica: enormous sapphire and pale blue sculptural icebergs, an emperor penguin with its chick in the foreground, distant icy mountains beneath luminous soft pink and mint aurora, glittering ice crystals and calm mirror sea, enchanting crisp polar light. Deep navy, glacier cyan and pearl.

### japan

Background art ONLY for the ultimate Japan map collectible, no actual map or land shapes: sweeping deep midnight-blue ocean seen from above, sculptural soft pearl clouds curling around the LEFT and RIGHT EDGES, delicate golden sun rays entering from upper right, scattered tiny glowing golden flecks, subtle lacquer and washi paper textures. Keep the entire CENTRAL 65% an uninterrupted clean dark indigo sea for a geographically accurate Japan map that the app will overlay. No moon, no planet, no central object, no landscape, no symbols. Elegant Japanese golden-screen painting sensibility with richly painted cloud borders.


## 天・採用画像の編集プロンプト

組み込みImageGenで初回案②を編集：remove ONLY the sample number 02 near the bottom center, seamlessly reconstructing the dark blue clouds and fine gold linework. Keep the dragon, face, pose, colors, brightness, gem, sky, 天 title, border and composition unchanged.
