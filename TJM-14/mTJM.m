function [acc,acc_list,A] = mTJM(X_src,Y_src,X_tar,Y_tar,options)
% This is the implementation of Transfer Joint Matching.
% Reference: Mingsheng Long. Transfer Joing Matching for visual domain adaptation. CVPR 2014.

% Inputs:
%%% X_src          :     source feature matrix, ns * n_feature
%%% Y_src          :     source label vector, ns * 1
%%% X_tar          :     target feature matrix, nt * n_feature
%%% Y_tar          :     target label vector, nt * 1
%%% options        :     option struct
%%%%% lambda       :     regularization parameter
%%%%% dim          :     dimension after adaptation, dim <= n_feature
%%%%% kernel_tpye  :     kernel name, choose from 'primal' | 'linear' | 'rbf'
%%%%% gamma        :     bandwidth for rbf kernel, can be missed for other kernels
%%%%% T            :     n_iterations, T >= 1. T <= 10 is suffice

% Outputs:
%%% acc            :     final accuracy using knn, float
%%% acc_list       :     list of all accuracies during iterations
%%% A              :     final adaptation matrix, (ns + nt) * (ns + nt)
    
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    %% Set options
	lambda = options.lambda;              %% lambda for the regularization
	dim = options.dim;                    %% dim is the dimension after adaptation, dim <= m
	kernel_type = options.kernel_type;    %% kernel_type is the kernel name, primal|linear|rbf
	gamma = options.gamma;                %% gamma is the bandwidth of rbf kernel
	T = options.T;                        %% iteration number
    
	fprintf('TJM: dim=%d  lambda=%f\n',dim,lambda);

	%% Set predefined variables
	X = [X_src',X_tar'];%输入矩阵
	X = X*diag(sparse(1./sqrt(sum(X.^2))));%做归一化
	ns = size(X_src,1);%源域样本数
	nt = size(X_tar,1);%目标域样本数
	[m,n] = size(X);%总样本数
    
    % Construct kernel matrix
%     K = kernel_tjm(kernel_type,X,[],gamma);%将数据X核变换

    % Construct centering matrix
    H = eye(n)-1/(n)*ones(n,n);%构造中心矩阵

    % Construct MMD matrix
    e = [1/ns*ones(ns,1);-1/nt*ones(nt,1)];
    C = length(unique(Y_src));%获得类别数
    M = e*e' * C;%构造MMD矩阵，此处为M0
    
    G = speye(n);%G初始化为稀疏单位阵
    Cls = [];
    % Transfer Joint Matching: JTM
    acc_list = [];
    for t = 1:T
        %%% Mc [If want to add conditional distribution]
        N = 0;
        if ~isempty(Cls) && length(Cls)==nt%if里面就是计算条件概率分布M
            for c = reshape(unique(Y_src),1,C)
                e = zeros(n,1);
                e(Y_src==c) = 1 / length(find(Y_src==c));
                e(ns+find(Cls==c)) = -1 / length(find(Cls==c));
                e(isinf(e)) = 0;
                N = N + e*e';
            end
        end
        M = M + N;%这里也就是条件概率+边缘概率的Mc矩阵

        M = M/norm(M,'fro');%归一化处理
        if strcmp(kernel_type,'primal')
            [A,~] = eigs(X*M*X'+lambda*speye(m),X*H*X',dim,'SM');
            Z = A'*X;
        else
            K = kernel_tjm(kernel_type,X,[],gamma);
            [A,~] = eigs(K*M*K'+lambda*G,K*H*K',dim,'SM');
            G(1:ns,1:ns) = diag(sparse(1./(sqrt(sum(A(1:ns,:).^2,2)+eps))));%更新G的值
            Z = A'*K;
        end
        Z = Z*diag(sparse(1./sqrt(sum(Z.^2))));%归一化
        Zs = Z(:,1:ns)';%变换后的源域数据
        Zt = Z(:,ns+1:n)';%变换后的目标域数据

        knn_model = fitcknn(Zs,Y_src,'NumNeighbors',1);
        Cls = knn_model.predict(Zt);
        acc = sum(Cls==Y_tar)/nt;
        acc_list = [acc_list;acc(1)];

        fprintf('[%d]  acc=%f\n',t,full(acc(1)));
    end
	fprintf('Algorithm JTM terminated!!!\n\n');
    
end


% With Fast Computation of the RBF kernel matrix
% To speed up the computation, we exploit a decomposition of the Euclidean distance (norm)
%
% Inputs:
%       ker:    'linear','rbf','sam'
%       X:      data matrix (features * samples)
%       gamma:  bandwidth of the RBF/SAM kernel
% Output:
%       K: kernel matrix

function K = kernel_tjm(ker,X,X2,gamma)

switch ker
    case 'primal'
        K = X;
    case 'linear'
        
        if isempty(X2)
            K = X'*X;
        else
            K = X'*X2;
        end

    case 'rbf'

        n1sq = sum(X.^2,1);
        n1 = size(X,2);

        if isempty(X2)
            D = (ones(n1,1)*n1sq)' + ones(n1,1)*n1sq -2*X'*X;
        else
            n2sq = sum(X2.^2,1);
            n2 = size(X2,2);
            D = (ones(n2,1)*n1sq)' + ones(n1,1)*n2sq -2*X'*X2;
        end
        K = exp(-gamma*D); 

    case 'sam'
            
        if isempty(X2)
            D = X'*X;
        else
            D = X'*X2;
        end
        K = exp(-gamma*acos(D).^2);

    otherwise
        error(['Unsupported kernel ' ker])
end
end