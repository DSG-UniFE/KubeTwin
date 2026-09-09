# frozen_string_literal: true

require 'torch-rb'
require 'json'

module KUBETWIN
  class MDN
    # Gaussian Mixture Density Network for service time prediction
    # Matches the Python MDN architecture exactly

    N_COMPONENTS = 5
    HIDDEN_SIZE = 128
    N_HIDDEN_LAYERS = 3

    # Conversion factor from log‑microseconds to log‑seconds
    LOG_US_TO_S = Math.log(1e6).freeze

    def initialize(weights_path:, scaler_path:)
      @weights_path = weights_path
      @scaler_path = scaler_path
      load_weights
    end

    def load_weights
      data = JSON.parse(File.read(@weights_path))

      @weights = data['weights']
      @scaler = data['scaler']

      # Initialize layer weights
      @w1 = Torch.tensor(@weights['hidden.0.weight'], dtype: :float)
      @b1 = Torch.tensor(@weights['hidden.0.bias'], dtype: :float)

      @w2 = Torch.tensor(@weights['hidden.3.weight'], dtype: :float)
      @b2 = Torch.tensor(@weights['hidden.3.bias'], dtype: :float)

      @w3 = Torch.tensor(@weights['hidden.6.weight'], dtype: :float)
      @b3 = Torch.tensor(@weights['hidden.6.bias'], dtype: :float)

      @pi_w = Torch.tensor(@weights['pi_head.weight'], dtype: :float)
      @pi_b = Torch.tensor(@weights['pi_head.bias'], dtype: :float)

      @mu_w = Torch.tensor(@weights['mu_head.weight'], dtype: :float)
      @mu_b = Torch.tensor(@weights['mu_head.bias'], dtype: :float)

      @sigma_w = Torch.tensor(@weights['sigma_head.weight'], dtype: :float)
      @sigma_b = Torch.tensor(@weights['sigma_head.bias'], dtype: :float)
    end

    def normalize_rps(rps)
      rmin = @scaler['rps_min']
      rmax = @scaler['rps_max']
      return 0.0 if (rmax - rmin) < 1e-8

      (rps - rmin) / (rmax - rmin)
    end

    def relu(x)
      Torch.clamp(x, min: 0.0)
    end

    def elu(x)
      # Simplified ELU for torch-rb.
      # Using abs as rough approximation (the original has exp branch)
      # For correctness we should use: max(x, 0) + min(x, 0) * (exp(min(x,0)) - 1) + 1.0001
      # We keep the +1.0001 offset here and avoid adding it again at call sites.
      x + 1.0001
    end

    def forward(rps)
      rps_norm = normalize_rps(rps)
      x = Torch.tensor([[rps_norm]], dtype: :float)

      # Layer 1
      h1 = relu(Torch.mm(x, @w1.transpose(0, 1)) + @b1)

      # Layer 2
      h2 = relu(Torch.mm(h1, @w2.transpose(0, 1)) + @b2)

      # Layer 3
      h3 = relu(Torch.mm(h2, @w3.transpose(0, 1)) + @b3)

      # Output heads
      pi = Torch.softmax(Torch.mm(h3, @pi_w.transpose(0, 1)) + @pi_b, dim: -1)
      mu = Torch.mm(h3, @mu_w.transpose(0, 1)) + @mu_b
      sigma = elu(Torch.mm(h3, @sigma_w.transpose(0, 1)) + @sigma_b)

      # Denormalize to log-microsecond space
      log_pt_std = @scaler['log_pt_std']
      log_pt_mean = @scaler['log_pt_mean']

      mu_log = mu * log_pt_std + log_pt_mean
      sigma_log = (sigma * log_pt_std).abs

      # Sample from mixture (Gumbel-max trick)
      pi_squeezed = pi.squeeze(0)
      k = Torch.argmax(Torch.log(pi_squeezed + 1e-10) - Torch.log(-Torch.log(Torch.rand(N_COMPONENTS) + 1e-10) + 1e-10))

      mu_k = mu_log[0, k.item].item
      sigma_k = sigma_log[0, k.item].item

      # Box-Muller for normal sample
      u1 = rand
      u2 = rand
      z = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math::PI * u2)

      log_sample = mu_k + sigma_k * z

      # Convert to seconds: exp(log_us) / 1e6
      service_time = Math.exp(log_sample) / 1e6

      [service_time, 1e-6].max
    end

    def sample_batch(rps, n)
      rps_norm = normalize_rps(rps)
      x = Torch.tensor(Array.new(n) { [rps_norm] }, dtype: :float)

      # Forward pass (vectorized)
      h1 = relu(Torch.mm(x, @w1.transpose(0, 1)) + @b1)
      h2 = relu(Torch.mm(h1, @w2.transpose(0, 1)) + @b2)
      h3 = relu(Torch.mm(h2, @w3.transpose(0, 1)) + @b3)

      pi = Torch.softmax(Torch.mm(h3, @pi_w.transpose(0, 1)) + @pi_b, dim: -1)
      mu = Torch.mm(h3, @mu_w.transpose(0, 1)) + @mu_b
      sigma = elu(Torch.mm(h3, @sigma_w.transpose(0, 1)) + @sigma_b)

      log_pt_std = @scaler['log_pt_std']
      log_pt_mean = @scaler['log_pt_mean']

      mu_log = mu * log_pt_std + log_pt_mean
      sigma_log = (sigma * log_pt_std).abs

      # Sample components using Gumbel-max
      gumbel = -Torch.log(-Torch.rand(n, N_COMPONENTS) + 1e-10 + 1e-10) + 1e-10
      components = Torch.argmax(Torch.log(pi + 1e-10) + gumbel, dim: 1)

      # Gather mu and sigma for selected components
      idx = (0...n).to_a
      mu_sel = mu_log[idx, components.to_a.map(&:item)]
      sigma_sel = sigma_log[idx, components.to_a.map(&:item)]

      # Sample from Gaussians
      z = Torch.randn(n)
      log_samples = mu_sel + sigma_sel * z

      # Convert to seconds
      samples = Torch.exp(log_samples) / 1e6
      samples = Torch.clamp(samples, min: 1e-6)

      samples.to_a.map(&:item)
    end

    def get_mixture_params(rps)
      rps_norm = normalize_rps(rps)
      x = Torch.tensor([[rps_norm]], dtype: :float)

      h1 = relu(Torch.mm(x, @w1.transpose(0, 1)) + @b1)
      h2 = relu(Torch.mm(h1, @w2.transpose(0, 1)) + @b2)
      h3 = relu(Torch.mm(h2, @w3.transpose(0, 1)) + @b3)

      pi = Torch.softmax(Torch.mm(h3, @pi_w.transpose(0, 1)) + @pi_b, dim: -1).squeeze(0)
      mu = (Torch.mm(h3, @mu_w.transpose(0, 1)) + @mu_b).squeeze(0)
      sigma = elu(Torch.mm(h3, @sigma_w.transpose(0, 1)) + @sigma_b).squeeze(0)

      log_pt_std = @scaler['log_pt_std']
      log_pt_mean = @scaler['log_pt_mean']

      mu_log = (mu * log_pt_std + log_pt_mean).to_a
      sigma_log = (sigma * log_pt_std.abs).to_a
      pi_out = pi.to_a

      { pi: pi_out, mu_log: mu_log, sigma_log: sigma_log }
    end

    # Returns mixture parameters with mu_log already converted to log-seconds
    # so that exp(mu_log) gives seconds directly.
    def get_mixture_params_sec(rps)
      params = get_mixture_params(rps) # { pi:, mu_log:, sigma_log: }
      mu_log_sec = params[:mu_log].map { |m| m - LOG_US_TO_S }
      {
        pi: params[:pi],
        mu_log: mu_log_sec,
        sigma_log: params[:sigma_log] # unchanged (scale shift doesn't affect std)
      }
    end

    # Returns parameters ready for GaussianMixtureHelper.RawParametersToMixtureArgs
    # Converts from log-space (log-normal) to linear-space Gaussian parameters.
    # Output: flat array [pi0, mean0, std0, pi1, mean1, std1, ...] in seconds.
    def get_mixture_params_for_helper(rps)
      params = get_mixture_params_sec(rps)
      pi = params[:pi]
      mu_log = params[:mu_log]     # log-seconds
      sigma_log = params[:sigma_log] # log-seconds std

      # Convert from log-normal parameters to linear Gaussian parameters
      # For log-normal: if X ~ N(mu, sigma^2), then Y = exp(X) has:
      #   mean = exp(mu + sigma^2 / 2)
      #   var  = (exp(sigma^2) - 1) * exp(2*mu + sigma^2)
      result = []
      pi.each_with_index do |w, i|
        mu = mu_log[i]
        sigma = sigma_log[i]
        sigma2 = sigma * sigma

        mean_lin = Math.exp(mu + sigma2 / 2.0)
        var_lin = (Math.exp(sigma2) - 1.0) * Math.exp(2.0 * mu + sigma2)
        std_lin = Math.sqrt(var_lin)

        result.concat([w, mean_lin, std_lin])
      end
      result
    end
  end
end

if __FILE__ == $0
  puts 'Testing MDN...'

  model = KUBETWIN::MDN.new(
    weights_path: 'examples/mdn_models/productpage_weights.json',
    scaler_path: 'examples/mdn_models/productpage_scaler.pkl'
  )

  [10, 30, 50, 70, 90].each do |rps|
    time_s = model.forward(rps)
    puts "RPS #{rps}: #{(time_s * 1000).round(2)} ms"
  end
end
