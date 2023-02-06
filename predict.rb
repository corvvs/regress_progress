require "json"
require "scanf"

PathParameters = "params.json"

def get_params_from(path)
  params_str = IO.read(path)
  return JSON.parse(params_str)
end

def predict(params, km)
  params["t0"] + params["t1"] * km
end

def main
  params = get_params_from(PathParameters)
  $stdout.print "tell me \"km\" > "
  km, = $stdin.gets.scanf("%f")
  $stdout.puts "km told: #{km}"
  price = predict(params, km)
  $stdout.puts "price predicted: #{price}"
end

main
