% -----------------------------------------------------
% -- Simple MIMO simulator (v0.2)
% -- 2014 (c) studer@cornell.edu
% -----------------------------------------------------

function simpleMIMOsim(varargin)

  % -- set up default/custom parameters
  
  if isempty(varargin)
    
    disp('using default simulation settings and parameters...')
        
    % set default simulation parameters 
    par.simName = 'ProvaSDR1'; % simulation name (used for saving results)
    par.runId = 'default'; % simulation ID (used to reproduce results)
    par.MR = 5; % receive antennas 
    par.MT = 5; % transmit antennas (set not larger than MR!) 
    par.mod = 'QPSK'; % modulation type: 'BPSK','QPSK','16QAM','64QAM'
    par.trials = 750; % number of Monte-Carlo trials (transmissions)
    par.SNRdB_list = 15; % list of SNR [dB] values to be simulated
    par.detector = {'SDR RAND'}; % define detector(s) to be simulated
    
  else
      
    disp('use custom simulation settings and parameters...')    
    par = varargin{1}; % only argument is par structure
    
  end

  % -- initialization
  
  % use runId random seed (enables reproducibility)
  rng(par.runId); 

  % set up Gray-mapped constellation alphabet (according to IEEE 802.11)
  switch (par.mod)
    case 'BPSK',
      par.symbols = [ -1 1 ];
    case 'QPSK', 
      par.symbols = [ -1-1i,-1+1i, ...
                      +1-1i,+1+1i ];
    case '16QAM',
      par.symbols = [ -3-3i,-3-1i,-3+3i,-3+1i, ...
                      -1-3i,-1-1i,-1+3i,-1+1i, ...
                      +3-3i,+3-1i,+3+3i,+3+1i, ...
                      +1-3i,+1-1i,+1+3i,+1+1i ];
    case '64QAM',
      par.symbols = [ -7-7i,-7-5i,-7-1i,-7-3i,-7+7i,-7+5i,-7+1i,-7+3i, ...
                      -5-7i,-5-5i,-5-1i,-5-3i,-5+7i,-5+5i,-5+1i,-5+3i, ...
                      -1-7i,-1-5i,-1-1i,-1-3i,-1+7i,-1+5i,-1+1i,-1+3i, ...
                      -3-7i,-3-5i,-3-1i,-3-3i,-3+7i,-3+5i,-3+1i,-3+3i, ...
                      +7-7i,+7-5i,+7-1i,+7-3i,+7+7i,+7+5i,+7+1i,+7+3i, ...
                      +5-7i,+5-5i,+5-1i,+5-3i,+5+7i,+5+5i,+5+1i,+5+3i, ...
                      +1-7i,+1-5i,+1-1i,+1-3i,+1+7i,+1+5i,+1+1i,+1+3i, ...
                      +3-7i,+3-5i,+3-1i,+3-3i,+3+7i,+3+5i,+3+1i,+3+3i ];
                         
  end

  % extract average symbol energy
  par.Es = mean(abs(par.symbols).^2); 
  
  % precompute bit labels
  par.Q = log2(length(par.symbols)); % number of bits per symbol
  par.bits = de2bi(0:length(par.symbols)-1,par.Q,'left-msb');

  % track simulation time
  time_elapsed = 0;
  
  % -- start simulation 
  
  % initialize result arrays (detector x SNR)
  res.VER = zeros(length(par.detector),length(par.SNRdB_list)); % vector error rate
  res.SER = zeros(length(par.detector),length(par.SNRdB_list)); % symbol error rate
  res.BER = zeros(length(par.detector),length(par.SNRdB_list),75); % bit error rate

  % generate random bit stream (antenna x bit x trial)
  bits = randi([0 1],par.MT,par.Q,par.trials);

  % trials loop
  tic
  for t=1:par.trials
  
    % generate transmit symbol
    idx = bi2de(bits(:,:,t),'left-msb')+1;
    s = par.symbols(idx).';
  
    % generate iid Gaussian channel matrix & noise vector
    n = sqrt(0.5)*(randn(par.MR,1)+1i*randn(par.MR,1));
    H = sqrt(0.5)*(randn(par.MR,par.MT)+1i*randn(par.MR,par.MT));
    
    % transmit over noiseless channel (will be used later)
    x = H*s;
  
    % SNR loop
    for k=1:length(par.SNRdB_list)
      
      % compute noise variance (average SNR per receive antenna is: SNR=MT*Es/N0)
      N0 = par.MT*par.Es*10^(-par.SNRdB_list(k)/10);
      
      % transmit data over noisy channel
      y = x+sqrt(N0)*n;
    
      % algorithm loop      
      for d=1:length(par.detector)
          
        switch (par.detector{d}) % select algorithms
          case 'ZF', % zero-forcing detection
            [idxhat,bithat] = ZF(par,H,y);
          case 'bMMSE', % biased MMSE detector
            [idxhat,bithat] = bMMSE(par,H,y,N0);          
          case 'uMMSE', % unbiased MMSE detector
            [idxhat,bithat] = uMMSE(par,H,y,N0);
          case 'ML', % ML detection using sphere decoding
            [idxhat,bithat] = ML(par,H,y);
          case 'SDR SVD', % Semidefinite Relaxation detection
            [idxhat,bithat] = SDR(par,H,y,d); 
          case 'SDR RAND'
            [idxhat,bithat] = SDR(par,H,y,d);    
          otherwise,
            error('par.detector type not defined.')      
        end

        % -- compute error metrics
        for l=1:7
            display(l)
            err = (idx~=idxhat(l,:));
            res.VER(d,k) = res.VER(d,k) + any(err);
            res.SER(d,k) = res.SER(d,k) + sum(err)/par.MT;
            res.BER(d,k,l) = res.BER(d,k,l) + sum(sum(bits(:,:,t)~=bithat(l,:)))/(par.MT*par.Q);   
            display(bits(:,:,t))
            display(bithat(l,:))
            
        end
      end % algorithm loop
                 
    end % SNR loop    
    
    % keep track of simulation time    
    if toc>10
      time=toc;
      time_elapsed = time_elapsed + time;
      fprintf('estimated remaining simulation time: %3.0f min.\n',time_elapsed*(par.trials/t-1)/60);
      tic
    end      
    
  end % trials loop

  % normalize results
  res.VER = res.VER/par.trials;
  res.SER = res.SER/par.trials;
  res.BER = res.BER/par.trials;
  res.time_elapsed = time_elapsed;
  
  % -- save final results (par and res structure)
    
  save([ par.simName '_' num2str(par.runId) ],'par','res');    
    
  % -- show results (generates fairly nice Matlab plot) 
  
  marker_style = {'bo-','rs--','mv-.','kp:','g*-','c>--','yx:'};
  figure(1)
  j=1;
  for i=1:7
      semilogy(par.SNRdB_list,res.BER(1,:,i),marker_style{j},'LineWidth',2)
      hold on
      j=j+1;
  end
  
 hold off
 grid on
 xlabel('average SNR per receive antenna [dB]','FontSize',12)
 ylabel('bit error rate (BER)','FontSize',12)
 axis([min(par.SNRdB_list) max(par.SNRdB_list) 1e-4 1])
 legend('Num Random 1','Num Random: 13','Num. Random: 26','Num Random: 38','Num Random: 63','Num Random: 75')
 set(gca,'FontSize',12)

%   for d=1:length(par.detector)
%     if d==1
%       for i=1:7
%           semilogy(par.SNRdB_list,res.BER(d,:,i),marker_style{i},'LineWidth',2)
%           hold on
%       end
%       break
%     else
%       semilogy(par.SNRdB_list,res.BER(d,:),marker_style{d},'LineWidth',2)
%     end
%   end
%   hold off
%   grid on
%   xlabel('average SNR per receive antenna [dB]','FontSize',12)
%   ylabel('bit error rate (BER)','FontSize',12)
%   axis([min(par.SNRdB_list) max(par.SNRdB_list) 1e-4 1])
%   legend('Num Random 1','Num Random 13','Num Random 26','Num Random 38','Num Random 63','Num Random 75')
%   set(gca,'FontSize',12)
  
end

% -- set of detector functions 

%% SDR detector
function [idxhat,bithat] = SDR(par,H,y,d)

% SDR detector: Solves the problem || y-Hx||^2 by a SDP relaxation and then
% some rounding procedure that will be specified later on.

% First of all, construct real valued homogeneous QCQP to be solved by SDP programming
% I assume QPSK constellation s=+/-1+/-j  ( 2 bits/symbol)

% Convert real valued
y = [real(y); imag(y)];
H=[real(H), -imag(H);imag(H),real(H)];

% Construct auxiliary matrix
C=[ H'*H , -H'*y ; -y'*H , y'*y];

% Constraints
p=0; % Number of inequalities
m=2*(par.MT); % 2N equalities
n=m+1;

cvx_begin quiet
    variable X(n,n) symmetric 
    minimize(trace(C*X));
    subject to
          diag(X) == 1; 
          X == semidefinite(n);  
cvx_end
Xopt=X;




%%Gaussian Randomization Procedure to generate feasible points

if strcmp(par.detector{d},'SDR RAND')
    
    % To get rid of round-off errors, compute a truly PSD matrix
    [~,p]= chol(Xopt);
    if (p~=0)
       Xopt=nearestSPD(Xopt);
    end

    bithat=[];
    idxhat=[];
    for L=round(linspace(1,75,7))
        %Generate Random samples
        Xl=zeros(n,L);
        fobj=zeros(L,1);
        for l=1:L
            xl= mvnrnd(zeros(1,n)',Xopt); 
            xl=sign(xl');
            fobj(l)= xl'*C*xl;
            Xl(:,l)= xl;
        end
        [~,idxl]=min(fobj);
        xhat=Xl(:,idxl);

        %%Reconstruct bits

        if  xhat(end) == -1
            xhat=-xhat;
        end    
        sym = xhat(1:end-1); % extract slack variable
        sym = sym(1:par.MT)+1i*sym(par.MT+1:end);
        [~,id] = min(abs(sym*ones(1,length(par.symbols))-ones(par.MT,1)*par.symbols).^2,[],2); % Detect symbol 
        idxhat =[idxhat; id];
        b=par.bits(idxhat,:);
        b=b(:);
        bithat =[bithat ; b];% Demodulate to bits
    end
end

%%Applying a rank one approximation in the least 2-norm sense (By Eigenvalue Decomposition)

if strcmp(par.detector{d},'SDR SVD')
    
    % The svd only work fine if X is PSD (which was one of our contraints)
    [U,S,V]=svd(Xopt);
    largEigValue= S(1,1);
    largEigVector= U(:,1);
    x_opt = sqrt(largEigValue)*largEigVector;
    xhat = x_opt;
    xhat=sign(xhat);
    %%Reconstruct bits
    if  xhat(end) == -1
        xhat=-xhat;
    end    
    sym = xhat(1:end-1); % extract slack variable
    sym = sym(1:par.MT)+1i*sym(par.MT+1:end);
    [~,idxhat] = min(abs(sym*ones(1,length(par.symbols))-ones(par.MT,1)*par.symbols).^2,[],2); % Detect symbol 
    bithat = par.bits(idxhat,:); % Demodulate to bits

end

 
% In case of BPSK, we have a BQP to assure a feasible solution , we use the
% sgn(�) operator 



end

%% zero-forcing (ZF) detector
function [idxhat,bithat] = ZF(par,H,y)
  xhat = H\y;    
  [~,idxhat] = min(abs(xhat*ones(1,length(par.symbols))-ones(par.MT,1)*par.symbols).^2,[],2);
  bithat = par.bits(idxhat,:);
end

%% biased MMSE detector (bMMSE)
function [idxhat,bithat] = bMMSE(par,H,y,N0)
  xhat = (H'*H+(N0/par.Es)*eye(par.MT))\(H'*y);    
  [~,idxhat] = min(abs(xhat*ones(1,length(par.symbols))-ones(par.MT,1)*par.symbols).^2,[],2);
  bithat = par.bits(idxhat,:);  
end

%% unbiased MMSE detector (uMMSE)
function [idxhat,bithat] = uMMSE(par,H,y,N0)
  W = (H'*H+(N0/par.Es)*eye(par.MT))\(H');
  xhat = W*y;
  G = real(diag(W*H));
  [~,idxhat] = min(abs(xhat*ones(1,length(par.symbols))-G*par.symbols).^2,[],2);
  bithat = par.bits(idxhat,:);
end

%% ML detection using sphere decoding
function [idxML,bitML] = ML(par,H,y)

  % -- initialization  
  Radius = inf;
  PA = zeros(par.MT,1); % path
  ST = zeros(par.MT,length(par.symbols)); % stack  

  % -- preprocessing
  [Q,R] = qr(H,0);  
  y_hat = Q'*y;    
  
  % -- add root node to stack
  Level = par.MT; 
  ST(Level,:) = abs(y_hat(Level)-R(Level,Level)*par.symbols.').^2;
  
  % -- begin sphere decoder
  while ( Level<=par.MT )          
    % -- find smallest PED in boundary    
    [minPED,idx] = min( ST(Level,:) );
    
    % -- only proceed if list is not empty
    if minPED<inf
      ST(Level,idx) = inf; % mark child as tested        
      NewPath = [ idx ; PA(Level+1:end,1) ]; % new best path
      
      % -- search child
      if ( minPED<Radius )
        % -- valid candidate found
        if ( Level>1 )                  
          % -- expand this best node
          PA(Level:end,1) = NewPath;
          Level = Level-1; % downstep
          DF = R(Level,Level+1:end) * par.symbols(PA(Level+1:end,1)).';
          ST(Level,:) = minPED + abs(y_hat(Level)-R(Level,Level)*par.symbols.'-DF).^2;
        else
          % -- valid leaf found     
          idxML = NewPath;
          bitML = par.bits(idxML',:);
          % -- update radius (radius reduction)
          Radius = minPED;    
        end
      end      
    else
      % -- no more childs to be checked
      Level=Level+1;      
    end    
  end
  
end
