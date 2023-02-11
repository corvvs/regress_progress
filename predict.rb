#!/usr/bin/ruby

require "json"
require "scanf"

PathParameters = "params.json"

def get_params_from(path)
  params_str = begin
    IO.read(path)
  rescue => e
    # IOのエラーが起きた場合はデフォルト値を使う
    $stderr.puts e.message
    defparam = { "t0" => 0, "t1" => 0 }
    $stderr.puts "using default parameters: #{defparam}"
    return defparam
  end
  return JSON.parse(params_str)
end

def hypothesis(t0, t1, x)
  return t0 + t1 * x
end

def main
  params = get_params_from(PathParameters)
  fail "params.json has no data" if !params
  fail "params.json has unexpected data" if !(params["t0"].is_a? Numeric) || !(params["t1"].is_a? Numeric)
  fail "params.json has unexpected format" if !Float(params["t0"]) || !Float(params["t1"])

  print "tell me \"km\" > "
  km, = $stdin.gets.scanf("%f")
  fail "km is unexpected" if !km
  fail "km is not finite" if !km.finite?
  puts "km told: #{km}"
  t0 = params["t0"]
  t1 = params["t1"]
  price = hypothesis(t0, t1, km)
  fail "price is not finite" if !price.finite?
  puts "price predicted: #{price}"

rescue => e
  $stderr.puts [e.class, e.message] * " "
  exit 1
rescue => e
  exit 1
end

main()
