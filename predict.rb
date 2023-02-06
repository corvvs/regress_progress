#!/usr/bin/ruby

require "json"
require "scanf"

PathParameters = "params.json"

def get_params_from(path)
  params_str = IO.read(path)
  return JSON.parse(params_str)

rescue => e
  p e
  exit 1
end

def predict(params, km)
  params["t0"] + params["t1"] * km
end

def main
  params = get_params_from(PathParameters)
  fail "params.json has no data" if !params
  fail "params.json has unexpected data" if !params["t0"] || !params["t1"]
  fail "params.json has unexpected format" if !params["t0"].finite? || !params["t1"].finite?

  print "tell me \"km\" > "
  km, = $stdin.gets.scanf("%f")
  fail "km is unexpected" if !km
  fail "km is not finite" if !km.finite?
  puts "km told: #{km}"
  price = predict(params, km)
  fail "price is not finite" if !price.finite?
  puts "price predicted: #{price}"

rescue => e
  $stderr.puts e.inspect
  exit 1
rescue => e
  exit 1
end

main()
