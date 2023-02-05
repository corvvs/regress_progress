PathData = "data.csv"
LearningRate = 0.01

def get_csv_lines(csv_path)
  raw_schema, *raw_lines = IO.readlines(csv_path).map(&:chomp)
  # 1行目は schema であると仮定して捨てる
  # 2行目以降は, 数値データ2列からなるCSVであるかをチェックする.
  raw_lines
    .map{ |s| s.split(",") }
    .map{ |ss|
      fail "row size is not 2" if ss.size != 2
      km, price = ss.map{ |s| Float(s) }
      { km: km, price: price }
    }
end

def train(csv_path)
  csv_lines = get_csv_lines(csv_path)
  p csv_lines
end

train(PathData)
