require "json"

PathData = "data.csv"
PathParameters = "params.json"
LearningRate = 0.5
Iterations = 100000
Epsilon = 1e-10
Xi = 0.8

# 指定されたパスにあるCSVファイルからデータを取得する
def get_data_from_csv(csv_path)
  raw_schema, *raw_lines = IO.readlines(csv_path).map(&:chomp)
  # 1行目は schema であると仮定して捨てる
  # 2行目以降は, 数値データ2列からなるCSVであるかをチェックする.
  raw_lines
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

# 数値列 xs を平均 = 0, 分散 = 1になるように標準化するパラメータ a, b と, 標準化後の数値列 ns を返す.
# ns[i] = a * (xs[i] + b).
def standardizer(xs)
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

def hypothesis(t0, t1, x)
  t0 + t1 * x
end

def error2(data, params)
  t0 = params[:t0]
  t1 = params[:t1]
  data.map{ |d| (hypothesis(t0, t1, d[:x]) - d[:y]) ** 2    }.reduce(0, :+)
end

# パラメータを1段階変化させる
# returns {
#   error2: 誤差の自乗和
#   s0: error2 の t0 偏微分
#   s1: error2 の t1 偏微分
#   d0: s0 の変化分 (偏微分の符号を反転して学習率で適当にダウンスケールする)
#   d1: s1 の変化分
# }
def train_a_step(data, params)
  m = data.size
  t0 = params[:t0]
  t1 = params[:t1]
  error2 = error2(data, params)
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

def standardize_data(data)
  nx = standardizer(data.map{ |d| d[:x] })
  ny = standardizer(data.map{ |d| d[:y] })
  data = (0...nx[:ns].size).map{ |i| { x: nx[:ns][i], y: ny[:ns][i] } }
  [nx, ny, data]
end

def unstandardize_params(params, nx, ny)
  a = params[:t0]
  b = params[:t1]
  a, b = [(a + b * nx[:a] * nx[:b] - ny[:a] * ny[:b]) / ny[:a], b * nx[:a] / ny[:a]]
  return { t0: a, t1: b }
end

# データセット data を使って学習を実施する.
# data = { x: number[], y: number[] }
# 仮説として y = t0 + t1 * x を用いる(x = km, y = price).
# with_standardize == true の場合, データの標準化を行う.
# 標準化: x, y それぞれについて, 平均 = 0, 分散 = 1 となるように線形変換を施す.
def train(data, with_standardize = false)
  fail "no data" if data.size == 0

  f(data)

  nx = nil
  ny = nil
  if with_standardize then
    # data を標準化する
    nx, ny, data = standardize_data(data)
  end

  # パラメータ t0, t1: それぞれ初期値を [-l,+l] からランダムにとる.
  l = 10
  params = { t0: rand * l * 2 - l, t1: rand * l * 2 - l }
  rate = LearningRate
  Iterations.times { |i|
    a = params[:t0]
    b = params[:t1]
    if nx && ny then
      # 標準化を解除
      up = unstandardize_params(params, nx, ny)
      a = up[:t0]
      b = up[:t1]
    end
    $stderr.puts "f_#{i}(x) = #{a} + #{b} * x"

    delta = train_a_step(data, params)
    # 偏微分の大きさ
    ms = Math.sqrt(delta[:s0] ** 2 + delta[:s1] ** 2)

    while (true) do
      dp = { t0: params[:t0] + rate * delta[:d0], t1: params[:t1] + rate * delta[:d1] }
      e2 = delta[:error2]
      d2 = train_a_step(data, dp)
      e2d = d2[:error2]
      
      # Armijo条件
      break if e2d <= e2 + Xi * rate * ms
      rate *= 0.99
    end

    break if ms < Epsilon # イテレーション終了

    $stderr.puts "  ms = #{ms}"
    $stderr.puts "  rate = #{rate}"
    $stderr.puts "  error_#{i} = #{delta[:error2]}"
    params[:t0] += rate * delta[:d0]
    params[:t1] += rate * delta[:d1]
  }
  if nx && ny then
    unstandardize_params(params, nx, ny)
  else
    params
  end
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

# ds = get_data_from_boston
ds = get_data_from_csv(PathData)
params = train(ds, true)
write_params(params, PathParameters)
