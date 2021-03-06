function register_and_unmixing(oif_file, registerChannel, varargin)
% 
%   The following function program will register and perform channel 
%   separation on an image (.oif file). The registration algorithm will register the image by aligning
%   the selected channel on the same channel from the previous time point.
%
%   The unmixing (or channel separation) algorightm uses pca analysis to 
%   determine which channel each data point should be associated with. 
%
% Author: Jonathan Carroll-Nellenback

    if exist( fullfile('software','bioformats','5.3.3'), 'file') == 2   
        addpath( fullfile('.','utility_functions') );
        javaclasspath( fullfile('software','bioformats','5.3.3') );
    else
        addpath( fullfile('.','utility_functions') );
        addpath( fullfile('.','bfmatlab') );
        javaclasspath( fullfile('.','bfmatlab','bioformats_package.jar') );
    end
    

    % Prompt user for a file if given in input
    if nargin < 1
        [file, path] = uigetfile('*.*', 'Choose an .oif file to open');
        outputdir=[path,file,'.files'];
        oif_file = [path,file];
    else
        [path, file] = fileparts(oif_file);
        path = [path filesep];
        outputdir=[path,file,'.files'];
    end
    
    [dx,dy,dz,dt,data]=make5d(oif_file);
    [mx,my,mz,mc,mt]=size(data);

    %% Normalize the average intensity
    meanIntensity=mean(mean(mean(data,1),2),3);
    %data=uint16(single(data).*repmat(meanIntensity(:,:,:,:,1),my,mx,mz,1,mt)./repmat(meanIntensity,my,mx,mz,1,1));
    data=uint16(single(data).*repmat(meanIntensity(:,:,:,:,1),mx,my,mz,1,mt)./repmat(meanIntensity,mx,my,mz,1,1));

    %% Redo the pca analysis
    disp('Performing PCA (channel unmixing).');
    [coeff,data]=my_pca_shuffle(data,4); %get coefficients from first frame
    disp('PCA Complete.');
    
    %% And plot the results
    %data4d=uint16(squeeze(mean(data(:,:,:,:,:),3)));
    %bc=my_stretchlim(data4d)
    %playstack(data4d,bc,cmap)

    % prompt for channel for registration if not included in function
    % arguments.
    if nargin < 2
        clear zslice
        for i=1:size(data,5)
            zslice{i}=squeeze(uint16(mean(data(:,:,:,:,i),3))); %note mean returns a double so we need to convert it back to uint16
        end
        registerChannel = choose_channel(zslice);
    end

    
	% In case of z stack having less than 16 stacks, add empty stacks
    if mz < 16
        data(:,:,(mz+1):16,:,:) = 0;
    end

    %% Image registration
    [optimizer,metric]=imregconfig('monomodal')
    optimizer.MaximumIterations=300;

    %% register stack
    for i=1:mt
        disp(['Registration step ', num2str(i), ' of ', num2str(mt) ])
        moving=data(:,:,:,registerChannel,i); % modified to use selected channel - chris
        fixed=data(:,:,:,registerChannel,max(1,i-1)); % modified to use selected channel - chris
        tform{i}=imregtform(moving,fixed,'translation',optimizer,metric);
    end

    %% Accumulate transforms by matrix multiplication
    for i=2:mt
        tform{i}.T=tform{i-1}.T*tform{i}.T;
    end

    %% Apply the transform to ALL channels
    for i=1:mt
        for j=1:mc
%            data(:,:,:,j,i)=imwarp(data(:,:,:,j,i),tform{i},'OutputView',imref3d([mx,my,max(mz,16)]));
            data(:,:,:,j,i)=imwarp(data(:,:,:,j,i),tform{i},'OutputView',imref3d([mx,my,max(mz,16)]));
        end
    end

    % cuts off empty stacks if added
    data = data(:,:,1:mz,:,:);
    data = uint16(data);
    
    %%
	disp('Saving Output File');

	save([path,file,'.mat'],'tform','meanIntensity','coeff');
    savedata(data,outputdir)
    
    disp('Program completed');
    
end