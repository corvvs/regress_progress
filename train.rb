#!/usr/bin/ruby

require 'optparse'
require "json"

# 指定されたパスにあるCSVファイルからデータを取得する
def get_data_from_csv(csv_path)
  raw_schema, *raw_lines = IO.readlines(csv_path).map(&:chomp)
  # 1行目は schema であると仮定して捨てる
  # 2行目以降は, 数値データ2列からなるCSVであるかをチェックする.
  fail "no data line" if !raw_lines
  fail "no enough data lines" if raw_lines.size < 2
  return raw_lines
    .map{ |s| s.split(",") }
    .map{ |ss|
      fail "row size is not 2" if ss.size != 2
      km, price = ss.map{ |s| Float(s) }
      { x: km, y: price }
    }
end

# ボストンデータセット("./boston.txt"にあると仮定)から x = 部屋の広さ, y = 価格 と仮定してデータを取得する
def get_data_from_boston
  raw_lines = IO.readlines("./boston.txt").map(&:chomp)[22..-1]
  fs = raw_lines
    .map{ |s| s.strip.split(/\s+/) }.flatten
    .map{ |s| Float(s) }
  (0...fs.size)
    .chunk{ |i| i / 14 }
    .map{ |_, is| is.map{ |i| fs[i] } }
    .map{ |fs|
      room = fs[5]
      price = fs[-1]
      { x: room, y: price }
    }
end

# 精度パラメータを計算する
def get_precision(data, params)
  t0 = params[:t0]
  t1 = params[:t1]
  # error2
  pe2 = data.map{ |d| (d[:y] - hypothesis(t0, t1, d[:x])) ** 2 }.reduce(0, :+)
  error2 = pe2

  # R2
  obs_mean = data.map{ |d| d[:y] }.reduce(0, :+) / data.size
  oe2 = data.map{ |d| (d[:y] - obs_mean) ** 2 }.reduce(0, :+)
  r2 = 1 - pe2 / oe2

  # RMSE
  rmse = Math.sqrt(pe2 / data.size)

  # MAE
  pe1 = data.map{ |d| (d[:y] - hypothesis(t0, t1, d[:x])).abs }.reduce(0, :+)
  mae = pe1 / data.size

  { error2: error2, R2: r2, RMSE: rmse, MAE: mae }
end

def stringify_precision(precision)
  sprintf("  Error2: %f\n  R2: %f\n  RMSE: %f\n  MAE: %f", precision[:error2], precision[:R2], precision[:RMSE], precision[:MAE])
end

# 数値列 xs を平均 = 0, 分散 = 1になるように標準化するパラメータ a, b と, 標準化後の数値列 ns を返す.
# ns[i] = a * (xs[i] + b).
def standardize(xs)
  n = xs.size
  sx = xs.reduce(0) { |s,x| s + x }
  # Σ(x + b) = 0 となるように b を決定
  b = -sx / n
  # -> y = x + b
  # Σ(a * y)^2 = 1 となるように a を決定
  syy = xs.reduce(0) { |s,x| s + (x + b) ** 2 }
  a = 1 / Math.sqrt(syy)
  ns = xs.map{ |x| a * (x + b) }
  { a: a, b: b, ns: ns }
end

# 「データを」標準化する
def standardize_data(data)
  nx = standardize(data.map{ |d| d[:x] })
  ny = standardize(data.map{ |d| d[:y] })
  data = (0...nx[:ns].size).map{ |i| { x: nx[:ns][i], y: ny[:ns][i] } }
  [nx, ny, data]
end

# 「パラメータの」標準化を解除する
def unstandardize_params(params, nx, ny)
  a = params[:t0]
  b = params[:t1]
  a, b = [(a + b * nx[:a] * nx[:b] - ny[:a] * ny[:b]) / ny[:a], b * nx[:a] / ny[:a]]
  fail "a is not finite" if !a.finite?
  fail "b is not finite" if !b.finite?
  return { **params, t0: a, t1: b }
end

def hypothesis(t0, t1, x)
  t0 + t1 * x
end

# パラメータを1段階変化させる
# returns {
#   error2: 誤差の自乗和
#   s0: error2 の t0 偏微分
#   s1: error2 の t1 偏微分
#   d0, d1: s0, s1 をもとにした移動方向ベクトル
# }
def train_a_step(data, params)
  # assumed m > 0
  m = data.size
  t0 = params[:t0]
  t1 = params[:t1]
  error2 = data.map{ |d| (hypothesis(t0, t1, d[:x]) - d[:y]) ** 2    }.reduce(0, :+)
  s0     = data.map{ |d| (hypothesis(t0, t1, d[:x]) - d[:y])         }.reduce(0, :+)
  s1     = data.map{ |d| (hypothesis(t0, t1, d[:x]) - d[:y]) * d[:x] }.reduce(0, :+)
  return {
    error2: error2,
    s0: s0,
    s1: s1,
    d0: -s0 / m,
    d1: -s1 / m,
  }
end

# データセット data を使って学習を実施する.
# data = { x: number[], y: number[] }
# 仮説として y = t0 + t1 * x を用いる(x = km, y = price).
def train(settings, data)
  fail "no data" if data.size == 0

  nx = nil
  ny = nil
  if settings[:with_standardize] then
    # data を標準化する
    nx, ny, data = standardize_data(data)
  end

  # パラメータ t0, t1: それぞれ初期値を [-l,+l] からランダムにとる.
  l = 10
  params = { t0: rand * l * 2 - l, t1: rand * l * 2 - l, error2: Float::INFINITY, iterations: 0 }
  rate = settings[:initial_learning_rate]
  settings[:max_iterations].times { |i|

    delta = train_a_step(data, params)
    # 偏微分の大きさ
    ms = Math.sqrt(delta[:s0] ** 2 + delta[:s1] ** 2)
    fail "ms is not finite" if !ms.finite?
    break if ms < settings[:epsilon] # イテレーション終了

    while (true) do
      dp = {
        t0: params[:t0] + rate * delta[:d0],
        t1: params[:t1] + rate * delta[:d1],
      }
      e2 = delta[:error2]
      d2 = train_a_step(data, dp)
      e2d = d2[:error2]
      
      # Armijo条件
      break if e2d <= e2 + settings[:xi] * rate * ms
      rate *= 0.99
    end

    params[:t0] += rate * delta[:d0]
    params[:t1] += rate * delta[:d1]
    params[:error2] = delta[:error2]
    params[:iterations] += 1
  }
  if nx && ny then
    # データが標準化されているなら, パラメータの標準化を解除して返す
    return unstandardize_params(params, nx, ny)
  else
    return params
  end
end

# 学習セッティングに従い, dataを使って学習を行う
def trains(settings, data)
  results = []
  idx = (0...data.size).to_a.shuffle
  n_parts = settings[:n_parts]
  fail "less data size" if data.size / n_parts < 2
  n_parts.times { |i|
    begin
      train_data = (0...data.size).reject{ |j| idx[j] % n_parts == i }.map{ |j| data[j] }
      validation_data = (0...data.size).select{ |j| idx[j] % n_parts == i }.map{ |j| data[j] }
      params = train(settings, train_data)
      nth = i + 1
      puts sprintf("[trial #%d in %u iterations]\nt0: %f t1: %f",
        nth, params[:iterations], params[:t0], params[:t1],
      )
      precision = get_precision(validation_data, params)
      puts stringify_precision(precision)
      results << { **params, **precision, nth: nth, train_data: train_data, validation_data: validation_data }
    rescue => e
      # 学習中のエラーはスルーして次へ
      $stderr.puts e.message
      next
    end
  }
  fail "no valid results" if results.size < 1
  picked = results.min_by{ |p| p[:error2] }
  puts sprintf("picked: iteration #%d\nt0: %f t1: %f", picked[:nth], picked[:t0], picked[:t1])
  puts stringify_precision(picked)
  return picked
end

# 検算用: 解析解など
def f(data)
  m = data.reduce(0) { |s,d| s + 1 }
  xx = data.reduce(0) { |s,d| s + d[:x] ** 2 }
  y  = data.reduce(0) { |s,d| s + d[:y] }
  x  = data.reduce(0) { |s,d| s + d[:x] }
  xy = data.reduce(0) { |s,d| s + d[:x] * d[:y] }
  yy = data.reduce(0) { |s,d| s + d[:y] ** 2 }

  aa = m
  bb = xx
  a  = -2 * y
  ab = 2 * x
  b  = -2 * xy
  co = yy

  # 自乗誤差関数 err
  err = ->(x, y){ aa * x * x + bb * y * y + a * x + ab * x * y + b * y + co }
  # err の a による偏微分
  err_a = ->(x, y){ 2 * aa * x + a + ab * y }
  # err の b による偏微分
  err_b = ->(x, y){ 2 * bb * y + ab * x + b }

  # err の解析形
  puts "g(a, b) = #{aa} * a * a + #{bb} * b * b + #{a} * a + #{ab} * a * b + #{b} * b + #{co}"
  puts "ga(a, b) = 2 * #{aa} * a + #{a} + #{ab} * b"
  puts "gb(a, b) = 2 * #{bb} * b + #{ab} * a + #{b}"

  puts "gaa(a, b) = 2 * #{aa}"
  puts "gab(a, b) = #{ab}"
  puts "gbb(a, b) = 2 * #{bb}"
  # ヘッセ行列式
  # 線形回帰の場合はa, bに依存しない.
  # これが正ならerrは凸関数なので, 局所最適が大域最適になる.
  puts "hessian = #{2 * aa * 2 * bb - ab * ab}"

  na = (xx * y - x * xy) / (m * xx - x * x)
  nb = (m * xy - x * y) / (m * xx - x * x)
  # 解析的に最適な回帰式
  puts "na = #{na}"
  puts "nb = #{nb}"
  [err, err_a, err_b]
end

def write_params(params, path)
  File.open(path, "w") { |f|
    f.write(JSON.unparse(params))
  }
end

def write_gnuplot(settings, result)
  # datファイル
  File.open(PathGnuplotData, "w") { |f|
    result[:train_data].each{ |d|
      f.puts sprintf("%f %f", d[:x], d[:y])
    }
    f.puts
    f.puts
    result[:validation_data].each{ |d|
      f.puts sprintf("%f %f", d[:x], d[:y])
    }
  }
  # gpファイル
  File.open(PathGnuplotGp, "w") { |f|
    f.puts <<-"EOF"
    t0 = "#{result[:t0]}"
    t1 = "#{result[:t1]}"
    f(x) = t0 + t1 * x
    plot "#{PathGnuplotData}" index 0 title "Training Data", f(x) title "Prediction", "#{PathGnuplotData}" index 1 title "Validation Data"
    EOF
  }
end


PathData = "data.csv"
PathParameters = "params.json"
LearningRate = 0.5
Parts = 6
Iterations = 100000
Epsilon = 1e-10
Xi = 0.8
PathGnuplotGp = "gnuplot.gp"
PathGnuplotData = "gnuplot.dat"

# オプションを解析し, 学習セッティングを変更する
def parse_opt
  settings = {
    # csvファイルのパス
    path_data: PathData,
    # パラメータの保存先
    path_params: PathParameters,
    # 標準化を行うかどうか
    # 標準化: x, y それぞれについて, 平均 = 0, 分散 = 1 となるように線形変換を施す.
    with_standardize: true,
    # 学習率の初期値
    initial_learning_rate: LearningRate,
    # クロスバリデーションにおける分割数
    n_parts: Parts,
    # 最大イテレーション
    max_iterations: Iterations,
    # エラーイプシロン: 「誤差自乗和の勾配ベクトルの大きさ」がこの値を下回るとイテレーションを終える
    epsilon: Epsilon,
    # Arumijo条件におけるパラメータξ
    xi: Xi,
    # gnuplot用gpファイル, datファイルを出力するかどうか
    write_gnuplot: false,
  }

  opt = OptionParser.new { |opt|
    opt.on('-p number of partition', Integer) { |v|
      raise OptionParser::InvalidArgument.new("required: >= 2") if v < 2
      settings[:n_parts] = v
    }
    opt.on('-t max number of iterations', Integer) { |v|
      raise OptionParser::InvalidArgument.new("required: >= 1") if v < 1
      settings[:max_iterations] = v
    }
    opt.on('-i data_file_path', String) { |v|
      settings[:path_data] = v
    }
    opt.on('-o json_file_path', String) { |v|
      settings[:path_params] = v
    }
    opt.on('-e epsilon for iteration', Float) { |v|
      raise OptionParser::InvalidArgument.new("required: > 0") if v <= 0
      settings[:epsilon] = v
    }
    opt.on('-x xi for Armijo Condition', Float) { |v|
      raise OptionParser::InvalidArgument.new("required: > 0") if v <= 0
      settings[:xi] = v
    }
    opt.on('-g') { |v|
      settings[:write_gnuplot] = true
    }
  }
  opt.parse(ARGV)
  return settings
end

def main
  settings = parse_opt
  # data = get_data_from_boston
  data = get_data_from_csv(settings[:path_data])
  result = trains(settings, data)
  write_params(result, settings[:path_params])
  if settings[:write_gnuplot]
    write_gnuplot(settings, result)
  end

# 例外はすべて exit 1
rescue => e
  $stderr.puts e.message
  exit 1
rescue => e
  exit 1
end

main()
