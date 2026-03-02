clear; clc; close all;
rng(1);

mu1 = 1;          % E[R1]
mu2 = 1;          % E[R2]

% just for generating mkt data
sig1_true = 0.1;
sig2_true = 0.1;

rhoList = -0.9:0.1:0.9;
nRho = length(rhoList);

nMC_prices = 1e6;       %use to approximate expected values using LLN

%size of the basis
m1 = 3;
m2 = 3;
mz = 3;

%Estimate sigmas
mSig = 10;          % choose nb of strikes for estimating sigma 
nGridSig = 1500;    % grid points for the 1D projection

% strikes and interval for estimating sigma

Isig1 = norminv([0.01,0.99],mu1,sig1_true);
Isig2 = norminv([0.01,0.99],mu2,sig2_true);

% we generate "market" marginal samples
R1_mkt = mu1 + sig1_true * randn(nMC_prices,1);
R2_mkt = mu2 + sig2_true * randn(nMC_prices,1);

Ksig1 = prctile(R1_mkt, linspace(10,90,mSig))';
Ksig2 = prctile(R2_mkt, linspace(10,90,mSig))';

%estimate sig1
s1Grid = linspace(Isig1(1), Isig1(2), nGridSig)';
Y1 = (s1Grid - 1).^2;

X1 = ones(nGridSig, 2 + mSig);
X1(:,2) = s1Grid;

X1(:,3:end) = max(s1Grid - Ksig1', 0); 

theta1 = X1 \ Y1;

basisMean1 = zeros(2+mSig,1);
basisMean1(1) = 1;
basisMean1(2) = mu1;
basisMean1(3:end) = mean(max(R1_mkt - Ksig1', 0));


sig1 = sqrt(max(theta1' * basisMean1, 0));

%estimate sig2
s2Grid = linspace(Isig2(1), Isig2(2), nGridSig)';
Y2 = (s2Grid - 1).^2;

X2 = ones(nGridSig, 2 + mSig);
X2(:,2) = s2Grid;
X2(:,3:end) = max(s2Grid - Ksig2', 0);

theta2 = X2 \ Y2;

basisMean2 = zeros(2+mSig,1);
basisMean2(1) = 1;
basisMean2(2) = mu2;
basisMean2(3:end) = mean(max(R2_mkt - Ksig2', 0), 1)'; 

sig2 = sqrt(max(theta2' * basisMean2, 0));





%grid projection 
I1 = [mu1 - 2*sig1, mu1 + 2*sig1];   %decreasing the interval makes it better, with 4*sig it is very bad
I2 = [mu2 - 2*sig2, mu2 + 2*sig2];

K1 = prctile(R1_mkt, linspace(10,90,m1))';
K2 = prctile(R2_mkt, linspace(10,90,m2))';

nGrid1 = 700;
nGrid2 = 700;

r1Grid = linspace(I1(1), I1(2), nGrid1)';
r2Grid = linspace(I2(1), I2(2), nGrid2)';

[R1g, R2g] = meshgrid(r1Grid, r2Grid); %i use g for grid 
R1vec = R1g(:);
R2vec = R2g(:);

% g(R1,R2) = (R1-1)(R2-1)
Y = (R1vec - 1) .* (R2vec - 1);

% compute "market" prices for univariate call basis using MC marginals
E_call1 = zeros(m1,1);
E_call1 = mean(max(R1_mkt - K1', 0), 1)';

E_call2 = zeros(m2,1);
E_call2 = mean(max(R2_mkt - K2', 0), 1)'; 

%loop over rho and estimate the correlation via projection
trueCorr = zeros(nRho,1);
estCorr  = zeros(nRho,1);
absErr   = zeros(nRho,1);

for t = 1:nRho
    rho = rhoList(t);

    trueCorr(t) = rho;   %it simplifies to just rho

    % Joint MC market prices for interaction basis depend on rho
    Sigma_true = [sig1_true^2, rho*sig1_true*sig2_true;
                  rho*sig1_true*sig2_true, sig2_true^2];

    R = mvnrnd([mu1 mu2], Sigma_true, nMC_prices);
    R1s = R(:,1);
    R2s = R(:,2);

    ratioMC = R1s ./ R2s; %abs(R2s).* sign(R2s);  
    Kz = linspace(prctile(ratioMC,10), prctile(ratioMC,90), mz)';

    % Build X on the grid 
    nObs = length(R1vec);
    nCols = 1 + 1 + m1 + 1 + m2 + mz;

    X = ones(nObs, nCols);

    % R1 column
    X(:,2) = R1vec;

    % (R1 - K1)+ columns
    X(:,3:2+m1) = max(R1vec - K1', 0); 

    % R2 column
    colR2 = 2 + m1 + 1;
    X(:,colR2) = R2vec;

    % (R2 - K2)+ columns
    X(:,colR2+1:colR2+m2) = max(R2vec - K2', 0);

    % Interaction columns R2 * max(R1/R2 - Kz, 0)  
    colZ = colR2 + m2 + 1;
    ratioGrid = R1vec ./ abs(R2vec).* sign(R2vec);

    X(:,colZ:colZ+mz-1) = R2vec .* max(ratioGrid - Kz', 0);

    % Projection 
    theta = X \ Y;

    % Expectations of basis functions
    basisMean = zeros(nCols,1);

    basisMean(1) = 1;
    basisMean(2) = mu1;
    basisMean(3:2+m1) = E_call1;

    basisMean(colR2) = mu2;
    basisMean(colR2+1:colR2+m2) = E_call2;

    basisMean(colZ:colZ+mz-1) = mean(R2s .* max(ratioMC - Kz', 0), 1)';

   
    estCorr(t) = (theta' * basisMean) ./ (sig1 * sig2);

    absErr(t) = abs(trueCorr(t) - estCorr(t));
end

figure;
plot(rhoList, absErr, 'o-', 'LineWidth', 1.5);
grid on;
xlabel('\rho');
ylabel('Absolute error');
title('Estimation error');

figure;
plot(rhoList, trueCorr, 'k-', 'LineWidth', 2); hold on;
plot(rhoList, estCorr,  'o-', 'LineWidth', 1.5);
grid on;
xlabel('\rho');
ylabel('Correlation');
title('True correlation vs Estimated correlation');
legend('True', 'Estimated', 'Location', 'best');
