# frozen_string_literal: true

# Purpose: Define Kutter's formula coefficient and capacity calculation methods
# Inputs: Conduit height, gradient, Manning's N (test example: 48 inches, 100 ft/ft*100, 0.013)
# Outputs: Console output with full, 3/4, and 1/2 pipe capacity values
# Type: EX Script (utility functions)
# Hardening: nil-safety, zero-guard on division, input validation

def kutter_coefficient(gradient, roughness_n, conduit_height)
  raise "Invalid gradient" if gradient.nil? || gradient < 0.0
  raise "Invalid Manning's N" if roughness_n.nil? || roughness_n <= 0.0
  raise "Invalid conduit height" if conduit_height.nil? || conduit_height <= 0.0

  r = conduit_height.to_f / 48.0
  numerator = 41.65 + (0.00281 / (gradient / 100.0 + 0.0001)) + (1.811 / roughness_n)
  denominator = 1.0 + (numerator * roughness_n / (Math.sqrt(r) + 0.0001))
  numerator / denominator
end

def full_pipe_capacity(conduit_height, gradient, roughness_n)
  raise "Invalid inputs" if conduit_height.nil? || gradient.nil? || roughness_n.nil?

  a = (((conduit_height / 12.0)**2) * 0.78539)
  r = conduit_height.to_f / 48.0
  c = kutter_coefficient(gradient, roughness_n, conduit_height)
  q = a * c * Math.sqrt((r * gradient / 100.0) + 0.0001)
  q
end

def three_quarter_pipe_capacity(conduit_height, gradient, roughness_n)
  raise "Invalid inputs" if conduit_height.nil? || gradient.nil? || roughness_n.nil?

  theta = 2.0944
  r = conduit_height.to_f / 12.0
  area = Math::PI * (r**2) - (r**2 * (theta - Math.sin(theta)) / 2.0)
  perimeter = (2.0 * Math::PI * r) - (r * theta)
  hydraulic_radius = area / (perimeter + 0.0001)
  c = kutter_coefficient(gradient, roughness_n, conduit_height)
  q = area * c * Math.sqrt((hydraulic_radius * gradient / 100.0) + 0.0001)
  q
end

def half_pipe_capacity(full_capacity)
  raise "Invalid full capacity" if full_capacity.nil?
  0.5 * full_capacity
end

begin
  puts "[#{Time.now.strftime('%H:%M:%S')}] Starting Kutter coefficient and capacity calculation"

  conduit_height = 48.0
  gradient = 100.0
  roughness_n = 0.013

  puts "[#{Time.now.strftime('%H:%M:%S')}] Input: height=#{conduit_height} in, gradient=#{gradient} ft/ft*100, n=#{roughness_n}"

  full_capacity = full_pipe_capacity(conduit_height, gradient, roughness_n)
  three_quarter_capacity = three_quarter_pipe_capacity(conduit_height, gradient, roughness_n)
  half_capacity = half_pipe_capacity(full_capacity)

  puts "Diameter: #{conduit_height} inches"
  puts "Slope: #{gradient / 100.0} ft/ft"
  puts "Manning's N Roughness: #{roughness_n}"
  puts "Kutter's Full Capacity (CFS): #{full_capacity.round(4)}"
  puts "Kutter's 3/4 Capacity (CFS): #{three_quarter_capacity.round(4)}"
  puts "Kutter's 1/2 Capacity (CFS): #{half_capacity.round(4)}"

  puts "[#{Time.now.strftime('%H:%M:%S')}] Calculation complete"

rescue => e
  puts "[#{Time.now.strftime('%H:%M:%S')}] Fatal error: #{e.message}"
  puts e.backtrace.first(5)
ensure
  puts "[#{Time.now.strftime('%H:%M:%S')}] Script ended"
end
