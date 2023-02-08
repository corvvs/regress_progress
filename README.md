## 必要なもの

- Ruby 2.6.8以降
  - `/usr/bin/ruby`にrubyコマンドがあってパスが通っていてほしい
- グラフ描画するには
  - gnuplot

## 手順

1. `./train.rb` でモデルパラメータを作成
2. `./predict.rb` に対して距離を数値で入力すると, 予想価格が表示される

## グラフ表示


0. 必要なら`gnuplot`をインストールしておく
  - Macなら`brew install gnuplot`
  - 違ったら自分でがんばる
1. `./train.rb -g`で, 通常の出力に加えグラフ描画用のファイルが生成される
2. `gnuplot`を起動してコマンド `load "gnuplot.gp"` を入力すると, グラフが表示される

### グラフを画像で保存する場合

- `load`コマンドに先立って以下のコマンドを入れる:
  1. `set terminal png`
  2. `set output "pngファイル名"`


