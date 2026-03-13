%% Projection method: g(s) approximated using (cash + stock + calls)
clear; clc; close all;

%% Grid of stock prices
S0 = 15;
s  = (10:0.05:20)';     % evaluation grid
n  = length(s);

%% Target payoff
g = (s - S0).^2;
Y = g;

%% Strikes
K = 11:2:18;          
m = length(K);

%% Build design matrix X
% Columns: [1, s, (s-K1)^+, ..., (s-Km)^+]
X = zeros(n, 2 + m);
X(:,1) = 1;             % constant term a
X(:,2) = s;             % linear term b*s

for j = 1:m
    X(:, 2+j) = max(s - K(j), 0);
end

%% Least squares regression
beta = X \ Y;

%% Approximation
ghat = X * beta;

%% Plot
figure;
plot(s, g, 'LineWidth', 2); hold on;
plot(s, ghat, '--', 'LineWidth', 2);

% Draw vertical lines at strikes
for j = 1:m
    xline(K(j), ':', sprintf('$K=%g$', K(j)), ...
        'Interpreter', 'latex', 'LineWidth', 1.2);
end

grid on;
xlabel('Stock price $s$', 'Interpreter', 'latex');
ylabel('Payoff', 'Interpreter', 'latex');
title('Projection method: $g(s)$ approximated by cash + stock + call payoffs', ...
    'Interpreter', 'latex');

legend({'$g(s)=(s-S_0)^2$', ...
        '$\hat g(s)=a+bs+\sum_{j}\beta_j(s-K_j)^+$'}, ...
        'Interpreter','latex', 'Location','best');

%% Display coefficients
disp('Estimated coefficients (a, b, betas):');
disp(beta);
