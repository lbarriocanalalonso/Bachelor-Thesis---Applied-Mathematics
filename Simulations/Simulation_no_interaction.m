
clear; clc; close all;
rng(1); 

mu1 = 1;          % E[R1]
mu2 = 1;          % E[R2]
sig1 = 0.20;      % std of R1
sig2 = 0.30;      % std of R2

rhoList = -0.9:0.1:0.9;     % correlations to test
nRho = length(rhoList);


%Intervals (mean +/- 3 std)
I1 = [mu1 - 3*sig1, mu1 + 3*sig1];
I2 = [mu2 - 3*sig2, mu2 + 3*sig2];

m1 = 5;
m2 = 5;

K1 = linspace(I1(1) + 0.2*sig1, I1(2) - 0.2*sig1, m1)';
K2 = linspace(I2(1) + 0.2*sig2, I2(2) - 0.2*sig2, m2)';

nGrid1 = 60;
nGrid2 = 60;

r1Grid = linspace(I1(1), I1(2), nGrid1)';
r2Grid = linspace(I2(1), I2(2), nGrid2)';

[R1g, R2g] = meshgrid(r1Grid, r2Grid);
R1vec = R1g(:);
R2vec = R2g(:);

% g(R1,R2) = (R1-1)(R2-1)
Y = (R1vec - 1) .* (R2vec - 1);

%E[(X-K)+] for X ~ Normal(mu, sig)
normalCallMean = @(mu,sig,K) (mu-K).*normcdf((mu-K)./sig) + sig.*normpdf((mu-K)./sig);


trueCov = zeros(nRho,1);  %creates vecotrs with zero rows then we will store their actual values inside
estCov  = zeros(nRho,1);
absErr  = zeros(nRho,1);

for t = 1:nRho

    rho = rhoList(t); %takes t-index of the list created initially with the values that rho takes

    % True covariance under bivariate normal
    trueCov(t) = rho * sig1 * sig2;

   
    % Columns: [1, R1, (R1-K1_1)+,...,(R1-K1_5)+, R2, (R2-K2_1)+,...,(R2-K2_5)+]
    nObs = length(R1vec);   %nb of observations (here is 60x60=3600)
    X = ones(nObs, 1 + 1 + m1 + 1 + m2); %matrix of only ones, nObs= rows, 1+1+m1...=nb columns

    % the ones are for the cte terms: a, R1, R2 and m1 and m2 are the nb of
    % strikes 

    % R1 column
    X(:,2) = R1vec; %we replace that column with the values of R1: X_{k,2}=R_{1,k}

    % (R1 - K1_j)+ columns
    for j = 1:m1
        X(:,2+j) = max(R1vec - K1(j), 0);
    end

    % R2 column
    colR2 = 2 + m1 + 1;
    X(:,colR2) = R2vec;

    % (R2 - K2_i)+ columns
    for i = 1:m2
        X(:,colR2+i) = max(R2vec - K2(i), 0);
    end

    theta = lsqminnorm(X, Y);
    %we get the coefficients (a, b1, b2, \beta, \gamma)

    %expect
    basisMean = zeros(size(theta)); 

    basisMean(1) = 1;      % E[1]
    basisMean(2) = mu1;    % E[R1]

    for j = 1:m1
        basisMean(2+j) = normalCallMean(mu1, sig1, K1(j)); %see notes it's the formula derived with PDC and CDF
    end

    basisMean(colR2) = mu2; % E[R2]

    for i = 1:m2
        basisMean(colR2+i) = normalCallMean(mu2, sig2, K2(i));
    end

   
    estCov(t) = theta' * basisMean;

   
    absErr(t) = abs(trueCov(t) - estCov(t));

end


figure;
plot(rhoList, absErr, 'o-', 'LineWidth', 1.5);
grid on;
xlabel('\rho');
ylabel('Absolute error');
title('Estimation of the covariance');

figure;
plot(rhoList, trueCov, 'k-', 'LineWidth', 2); hold on;
plot(rhoList, estCov,  'o-', 'LineWidth', 1.5);
grid on;
xlabel('\rho');
ylabel('Covariance');
title('True covariance vs Estimated covariance');
legend('True covariance', 'Estimated covariance', 'Location', 'best');
