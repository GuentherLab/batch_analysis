
function out = batch_analysis(varargin)
% BATCH_ANALYSIS ROI-level analysis
%
% out = batch_analysis(field1, value1, field2, value2, ...)
% specifies anaysis options:
%       file           : excel file containing ROI-data
%                         - Columns with numeric contents and labeled [HEM]_[ROINAME]_[MEASURENAME]
%                           (e.g. lh_HG_VOLUME) are considered potential OUTCOME DATA in analyses, with:
%                             [HEM] = lh (for right hemisphere) or rh (for right hemisphere)
%                             [ROINAME] = any arbitrary ROI name (e.g. HG)
%                             [MEASURE] = any arbitrary measure name (e.g. VOLUME)
%                           in the analyses (see hemispheres/rois/measures entries below)
%                         - Other columns with numeric contents are considered potential COVARIATES
%                           in the analyses (see model_effects entry below)
%       worksheet      : excel worksheet containing ROI-data
%       rois           : list of roi(s) in each parcel (e.g. { {'aINS','pINS'}, {'HG'}, ... } )
%                         alternatively: 'lumped' for lumped ROIs, 'all' for all ROIs, and '?' (default)
%                         to launch a GUI prompt where users can select individual ROIs
%                        note: analyses are performed separately for each ROI group 
%       hemispheres    : list of hemisphere(s) to include in the analysis (e.g. {'lh','rh'} )
%                         valid entries are 'lh' left-hemisphere, 'rh' right-hemisphere
%                         default {'lh','rh'} ; analysis combined across both hemispheres 
%       measures       : list of measure(s) to include in the analysis (e.g. {'lgi','volume'} )
%                         valid entries are [MEASURENAME] portion of field names in file
%                         default all measures ; analysis combined across al measures 
%       model_effects  : list of effect(s) to include in the analysis (e.g. {'AllSubjects','age'} )
%                         valid entries are 'AllSubjects' (for an effect with 1's for all subjects)
%                         and any potential covariates included in data file
%       model_contrast : contrast (across modeleffects) to evaluate in the analysis (e.g. [0, 1] )
%
%       mselect        : [0/1] performs dimensionality reduction test to suggest outcome variable(s)
%       listvars       : [0/1] returns list of ROI and covariate names and data in structure:
%                           ROIs         : ROI names
%                           measures     : measure names
%                           hemispheres  : hemisphere names
%                           covariates   : covariate names
%                           ROI_data     : ROIs data
%                           COV_data     : Covariates data
%       out            : output structure with analysis results:
%                           ROIs         : ROI names
%                           measures     : measure names
%                           hemispheres  : hemisphere names
%                           covariates   : covariate names
%                           ROI_data     : ROIs data
%                           COV_data     : Covariates data
%                           Design       : Design matrix
%                           Contrast     : Between-subejcts contrast vector/matrix
%                           sign_ROIs    : list of significant ROIs (p-FDR<.05)
%                           F            : statistics (one value per ROI)
%                           dof          : degrees of freedom (one value per ROI)
%                           p            : uncorrected p-values (one value per ROI)
%                           pfdr         : FDR-corrected p-values (one value per ROI)
%                           desc         : stats description (one value per ROI) (e.g. 'F(#)=#, p=#')
%                           combined_F   : F stats when data combined across all ROIs
%                           combined_dof : degrees of freedom when data combined across all ROIs
%                           combined_p   : p-value when data combined across all ROIs
%                           combined_desc: stats description when data combined across all ROIs (e.g. 'F(#)=#, p=#')
%
%
% e.g.
% batch_analysis('file', 'example.xlsx', 'worksheet','DATA');
% batch_analysis('file', 'example.xlsx', 'worksheet','DATA', 'rois', {'aCO'}, 'model_effects',{'AllSubjects','Chronological_Age_Months'},'model_contrast',[0 1],'hemispheres','lh','measures',{'area','volume'});


% alfnie@gmail.com
% 2023

options=struct(...
    'file',[],...
    'worksheet',[],...
    'mselect',false,...
    'listvars',false,...
    'rois',{{}},...
    'hemispheres',{{}},...
    'measures',{{}},...
    'model_effects',{{}},...
    'model_contrast',[]);
out={};
for n=1:2:nargin-1
    assert(isfield(options,lower(varargin{n})),'unrecognized option %s',varargin{n});
    options.(lower(varargin{n}))=varargin{n+1};
end

if isempty(options.file),
    [tfilename,tpathname]=conn_fileutils('uigetfile','*.xlsx; *.xls','Select data file');
    if isequal(tfilename,0), return; end
    options.file=fullfile(tpathname,tfilename);
end

% READS FILE DATA
tfile={options.file};
if ~isempty(options.worksheet), tfile{end+1}=options.worksheet; end
[ss_data_num,ss_data_txt,ss_data]=xlsread(tfile{:});

ss_data=[ss_data];ss_data_num=[ss_data_num];ss_data_txt=[ss_data_txt];
ss_fields=ss_data(1,:); % field names

fieldsvalid=cellfun(@ischar,ss_fields);
match=cell(size(ss_fields));
match(fieldsvalid)=regexp(ss_fields(fieldsvalid),'^(lh|rh)_([^_]*)_([^_]*)$','tokens','once');
ROI_idx=find(cellfun('length',match)==3);
assert(~isempty(ROI_idx),'unable to find valid fields of the form [lh|rh]_[ROINAME]_[MEASURENAME] in file');
fprintf('Found %d [lh|rh]_[ROINAME]_[MEASURENAME] fields\n',numel(ROI_idx));
fields=cat(1,match{ROI_idx});
[uhemi,nill,ROI_hemi]=unique(fields(:,1));
[uname,nill,ROI_name]=unique(fields(:,2));
[umeas,nill,ROI_meas]=unique(fields(:,3));
ss_data(cellfun(@(x)isequal(x,'NaN')|isequal(x,'nan'),ss_data))={NaN};
data=cell2mat(ss_data(2:end,ROI_idx));
validsamples=~all(isnan(data),2);
data=data(validsamples,:);
sData=[numel(umeas),numel(uhemi),numel(uname)];
idx=sub2ind(sData,ROI_meas,ROI_hemi,ROI_name);
if numel(unique(idx))~=numel(idx),error('repeated ROI names'); end
Data=nan([size(data,1),sData]);
Data(:,idx)=data; % samples x MEASURES x HEM x ROIs
fprintf('Read %d samples\nRead %d measures (%s)\nRead %d hemispheres (%s)\nRead %d ROIs (%s)\n',size(Data,1),size(Data,2),sprintf('%s ',umeas{:}),size(Data,3),sprintf('%s ',uhemi{:}),size(Data,4),sprintf('%s ',uname{:}));
%Data(Data==0) = NaN; %% EHM

COV_idx=find(cellfun('length',match)~=3);
COV_idx=COV_idx(all(cellfun(@isnumeric,ss_data(2:end,COV_idx)),1));
COV_idx=COV_idx(~all(cellfun(@isnan,ss_data(2:end,COV_idx)),1));
data=cell2mat(ss_data(2:end,COV_idx));
data=data(validsamples,:);
Covariates=data;
COV_name=ss_fields(COV_idx);
assert(size(Covariates,1)==size(Data,1),'unequal number of samples in data (%d) and covariates (%d)',size(Data,1),size(Covariates,1));
fprintf('Read %d samples\nRead %d covariates (%s)\n',size(Covariates,1),size(Covariates,2),sprintf('%s ',COV_name{:}));


if options.mselect % Variable selection tests
    Data2=Data;
    Data2=Data2-mean(Data2,1,'omitnan');
    Data2(isnan(Data2))=0;
    Data2=Data2./sqrt(mean(Data2.^2,1));
    Data3=reshape(permute(Data2,[1,3,4,2]),[size(Data2,1)*size(Data2,3)*size(Data2,4),size(Data2,2)]);
    Data3(isnan(Data3))=0;
    [Q,D,R]=svd(Data3,0);
    fprintf('Cumulative variance explained by SVD components: %s\n',mat2str(100*cumsum(diag(D).^2)/trace(D.^2),4));
    fprintf('SVD factors: %s\n',mat2str(R));
    figure;bar(100*cumsum(diag(D.^2))/trace(D.^2)); xlabel('Number of PCA components kept'); ylabel('Percent variance explained');set(gca,'units','norm','position',[.2 .2 .6 .6]);set(gcf,'color','w');grid on; box off; set(gca,'ylim',[0 100],'ytick',0:20:100,'yticklabel',arrayfun(@(n)sprintf('%d%%',n),0:20:100,'uni',0));
    conn_print('fig_variableselection_01.jpg','-nogui');
    nmeas=size(Data2,2);

    % removing one measure
    err=nan(1,nmeas);for n1=1:nmeas,data3=Data3(:,setdiff(1:nmeas,[n1])); Data3fit=data3*(data3\Data3); err(n1)=mean(mean((Data3fit-Data3).^2))/mean(mean(Data3.^2));end; [mine,idx]=min(err(:)); %disp(mine); disp(err);
    [nill,idx]=min(err(:)); I_Meas=setdiff(1:nmeas,idx);
    fprintf('measures [%s] explained %.2f%% of variance\n',sprintf('%s ',umeas{I_Meas}),100*(1-err(idx)))
    figure;bar(100*(1-err)); xlabel('Variable removed'); ylabel('Percent variance kept');set(gca,'xtick',1:nmeas,'xticklabel',umeas,'xticklabelrotation',90,'units','norm','position',[.2 .2 .6 .6]);set(gcf,'color','w');grid on; box off; set(gca,'ylim',[0 100],'ytick',0:20:100,'yticklabel',arrayfun(@(n)sprintf('%d%%',n),0:20:100,'uni',0));
    conn_print('fig_variableselection_02.jpg','-nogui');

    % keeping two measures
    err=nan(nmeas);for n1=1:nmeas,for n2=n1+1:nmeas,data3=Data3(:,[n1 n2]); Data3fit=data3*(data3\Data3); err(n1,n2)=mean(mean((Data3fit-Data3).^2))/mean(mean(Data3.^2));end;end; [mine,idx]=min(err(:)); %disp(mine); disp(err);
    [nill,idx]=min(err(:)); [idx(1) idx(2)]=ind2sub(size(err),idx);
    fprintf('measures [%s] explained %.2f%% of variance\n',sprintf('%s ',umeas{idx}),100*(1-err(idx(1),idx(2))))
    figure;[i,j]=find(~isnan(err));bar(100*(1-err(~isnan(err)))); xlabel('Variables kept'); ylabel('Percent variance kept');set(gca,'xtick',1:numel(i),'xticklabel',arrayfun(@(i,j)sprintf('%s ',umeas{[i,j]}),i,j,'uni',0),'xticklabelrotation',90,'units','norm','position',[.2 .4 .6 .4]);set(gcf,'color','w');grid on; box off; set(gca,'ylim',[0 100],'ytick',0:20:100,'yticklabel',arrayfun(@(n)sprintf('%d%%',n),0:20:100,'uni',0));
    conn_print('fig_variableselection_03.jpg','-nogui');

    % removing two measures
    err=nan(nmeas);for n1=1:nmeas,for n2=n1+1:nmeas,data3=Data3(:,setdiff(1:nmeas,[n1 n2])); Data3fit=data3*(data3\Data3); err(n1,n2)=mean(mean((Data3fit-Data3).^2))/mean(mean(Data3.^2));end;end; [mine,idx]=min(err(:)); %disp(mine); disp(err);
    [nill,idx]=min(err(:)); [idx(1) idx(2)]=ind2sub(size(err),idx); I_Meas=setdiff(1:nmeas,idx);
    fprintf('measures [%s] explained %.2f%% of variance\n',sprintf('%s ',umeas{I_Meas}),100*(1-err(idx(1),idx(2))))
    figure;[i,j]=find(~isnan(err));bar(100*(1-err(~isnan(err)))); xlabel('Variables removed'); ylabel('Percent variance kept');set(gca,'xtick',1:numel(i),'xticklabel',arrayfun(@(i,j)sprintf('%s ',umeas{[i,j]}),i,j,'uni',0),'xticklabelrotation',90,'units','norm','position',[.2 .4 .6 .4]);set(gcf,'color','w');grid on; box off; set(gca,'ylim',[0 100],'ytick',0:20:100,'yticklabel',arrayfun(@(n)sprintf('%d%%',n),0:20:100,'uni',0));
    conn_print('fig_variableselection_04.jpg','-nogui');
    %Rbase=R(:,1:3);
    disp(char(umeas{I_Meas}))
end

if options.listvars % lists variables
    out=struct(...
        'ROIs',{uname},...
        'measures',{umeas},...
        'hemispheres',{uhemi},...
        'covariates',{COV_name},...
        'ROI_data',Data,...
        'COV_data',Covariates);
    return
end

% ROIs
if isempty(options.rois),
    options.rois=listdlg('name',['Select ROIs'],'PromptString','Select ROI(s) to include in the analysis','ListString',uname,'SelectionMode','multiple','ListSize',[300 300]);
    if isempty(options.rois), return; end
    options.rois=arrayfun(@(x){x},uname(options.rois),'uni',0); % one-ROI per parcel only
end
if isequal(options.rois,'lumped'), ROIs = {{'aINS'}, {'aMFg'}, {'aSTg'}, {'CMA'},{'dPrCG'},{'H'},{'IFo'}, {'IForb'}, {'IFt'},{'mPoCG'},{'mPrCG'},{'pMFg'}, {'preSMA'},{'pSTg'},{'SMA'},{'SMg'},{'vPoCG'},{'vPrCG'}}; %lumped rois only
elseif isequal(options.rois,'groups'), ROIs={{'aIFt', 'pIFt','aFO'},{'dIFo','vIFo','pFO'},{'IFr','FOC'},{'H'},{'vPMC','midPMC'},{'vMC','midMC','aCO'},{'vSC','pCO', 'midSC'},{'preSMA','SMA','dCMA'},{'aSMg','PO'},{'pSMg'},{'PT','pSTg','pdSTs'},{'PP','aSTg','adSTs'},{'aINS'},{'pIFs'}};
elseif isequal(options.rois,'speech'), ROIs = {{'aCO'}, {'aFO'}, {'aINS'}, {'aSMg'}, {'dCMA'}, {'dIFo'}, {'H'}, {'IFr'}, {'midMC'}, {'midPMC'}, {'midSC'}, {'pCO'}, {'pdSTs'}, {'pFO'}, {'pIFs'}, {'PO'}, {'preSMA'}, {'pSTg'}, {'PT'}, {'SMA'}, {'vIFo'}, {'vMC'}, {'vPMC'}, {'vSC'}}; %speech network
elseif isequal(options.rois,'extended'), ROIs = {{'AG'},{'aCG'},{'pCG'},{'aCO'},{'SFg'},{'aMFg'},{'FMC'},{'FOC'},{'FP'},{'H'},{'aINS'},{'pINS'},{'SMA'},{'LG'},{'OC'},{'PCN'},{'aPH'},{'pPH'},{'PO'},{'PP'},{'PT'},{'SCC'},{'aSMg'},{'pSMg'},{'SPL'},{'aSTg'},{'aMTg'},{'aITg'},{'pSTg'},{'pMTg'},{'pITg'},{'aTF'},{'pTF'},{'MTO'},{'ITO'},{'TOF'},{'TP'},{'preSMA'},{'vMC'},{'dMC'},{'adPMC'},{'mdPMC'},{'pdPMC'},{'vPMC'},{'adSTs'},{'avSTs'},{'pdSTs'},{'pvSTs'},{'vSC'},{'pCO'},{'dSC'},{'pMFg'},{'aIFs'},{'pIFs'},{'dIFo'},{'vIFo'},{'midPMC'},{'midMC'},{'midSC'},{'aFO'},{'pFO'},{'dCMA'},{'vCMA'},{'aIFt'},{'pIFt'},{'IFr'}};
elseif isequal(options.rois,'all'), ROIs = options.rois; % all
elseif ischar(options.rois), error('unrecognized ROI option %s (valid entries are a cell array list of rois, or the keywords ''all'' or ''lumped'')',options.rois);
else ROIs = options.rois;
end
%left
%ROIs = {{'pIFs','pTF','aIFs','PP','pPH','pCO','pINS','aCO','vSC','aSTg','AG','FP','pSMg','aMFg','dIFo','aINS','H','midSC','vIFo','aSMg','midMC','vMC','PO','pMFg','LG','TOF','pvSTs','pSTg','SPL','OC','PT','MTO','midPMC','pdSTs','vPMC','PCN','ITO','pITg','pFO','aTF','adSTs','aIFt','pMTg','SFg','pCG','FOC','dMC','aCG','pIFt'}};
%right
%ROIs = {{'AG','vMC','pSMg','MTO','aSTg','H','PP','vSC','pIFs','pCO','aCO','pINS','PO','OC','dIFo','SPL','aMFg','aINS','pdSTs','LG','FP','SFg','dSC','PT','pSTg','aSMg','pvSTs','vPMC','TOF','aIFs','aCG','midSC','vIFo','adSTs','midMC','dMC','pFO','PCN','pMFg','dCMA','pCG','SMA','midPMC','vCMA','pMTg','preSMA','pdPMC'}};
if ischar(ROIs), ROIs={ROIs}; end
I_ROIs={};
for n1=1:numel(ROIs)
    if ischar(ROIs{n1}), ROIs{n1}={ROIs{n1}}; end
    for n2=1:numel(ROIs{n1}),
        idx=find(strcmp(ROIs{n1}{n2},uname));
        assert(numel(idx)==1, 'ROI %s not present in dataset',ROIs{n1}{n2});
        I_ROIs{n1}(n2)=idx;
    end
end
Nrois = numel(I_ROIs);

% measures
if isempty(options.measures),
    options.measures=listdlg('name',['Select measures'],'PromptString','Select measure(s) to include in the analysis','ListString',umeas,'SelectionMode','multiple','ListSize',[300 300]);
    if isempty(options.measures), return; end
    options.measures=umeas(options.measures);
end
if ischar(options.measures), options.measures={options.measures}; end
[OK_Meas, I_Meas]=ismember(options.measures,umeas);
assert(all(OK_Meas),'unrecognized measures %s (valid entries are %s)',sprintf('%s ',options.measures{~OK_Meas}), sprintf('%s ',umeas{:}));

% hemispheres
if isempty(options.hemispheres),
    options.hemispheres=listdlg('name',['Select hemispheres'],'PromptString','Select hemisphere(s) to include in the analysis','ListString',uhemi,'SelectionMode','multiple','ListSize',[300 300]);
    if isempty(options.hemispheres), return; end
    options.hemispheres=uhemi(options.hemispheres);
end
if ischar(options.hemispheres), options.hemispheres={options.hemispheres}; end
[OK_Hem, I_Hem]=ismember(options.hemispheres,uhemi);
assert(all(OK_Hem),'unrecognized measures %s (valid entries are %s)',sprintf('%s ',options.hemispheres{~OK_Hem}), sprintf('%s ',uhemi{:}));

% model effects
if isempty(options.model_effects),
    tCOV_name=[{'AllSubjects'},COV_name(:)'];
    options.model_effects=listdlg('name',['Select subject-effects in GLM model'],'PromptString','Select subject-effect(s) to include in the analysis','ListString',tCOV_name,'SelectionMode','multiple','ListSize',[300 300]);
    if isempty(options.model_effects), return; end
    options.model_effects=tCOV_name(options.model_effects);
end
if ischar(options.model_effects), options.model_effects={options.model_effects}; end
[OK_effects, I_effects]=ismember(options.model_effects,COV_name);
OK_effects(ismember(options.model_effects,{'AllSubjects'}))=true;
assert(all(OK_effects),'unrecognized covariates %s (valid entries are %s)',sprintf('%s ',options.model_effects{~OK_effects}), sprintf('%s ',COV_name{:}));

% model contrast
if isempty(options.model_contrast),
    if numel(I_effects)==1, options.model_contrast=1;
    else
        answ=inputdlg(sprintf('Between-subjects contrast (vector with %d values)',numel(I_effects)),'',1,{mat2str(zeros(1,numel(I_effects)))});
        if isempty(answ), return; end
        options.model_contrast=str2num(answ{1});
    end
end

%% define model design
AllSubjects = ones(size(Data,1));
Design = zeros(size(Data,1),numel(I_effects));
Design(:,I_effects==0)=1;
Design(:,I_effects>0)=Covariates(:,I_effects(I_effects>0));
Contr = options.model_contrast;
assert(size(Contr,2)==size(Design,2),'mismatch number of columns in contrast vector/matrix (%d) and number of columns in design matrix (%d)',size(Contr,2),size(Design,2));
fprintf('Model Design : %s\nModel Contrast: %s\n',mat2str(Design),mat2str(Contr));
fprintf('ROIs: %d ROI groups\n',Nrois);
fprintf('Measures: %s\n',sprintf('%s ',umeas{I_Meas}));
fprintf('Hemispheres: %s\n',sprintf('%s ',uhemi{I_Hem}));

%% stats
P=[];F=[]; Stats={}; Dof={}; descr={};

% dataSave = []; %neeed to index into later
for n=1:Nrois+1 %for each ROI (+1 is for all rois together)
    if n>Nrois
        data=mean(Data(:,I_Meas,I_Hem,[I_ROIs{:}]),4);                   % data for lumped-ROI & measures of interest
        %data=data(:,:,2)-data(:,:,1);
        %data=sum(data,3);
        if 0
            dataX=data(:,1,:); dataX=dataX(:,:);
            dataY=data(:,2,:); dataY=dataY(:,:);
            for n1=1:size(dataY,2), dataY(:,n1)=dataY(:,n1) - [ones(size(dataX,1),1) dataX(:,n1)] * ([ones(size(dataX,1),1) dataX(:,n1)]\dataY(:,n1)); end
            data=dataY;
        end

    elseif 1
        data=Data(:,I_Meas,I_Hem,I_ROIs{n});                   % data for lumped-ROI & measures of interest
    elseif 1 % measure2 controlled by measure1
        dataX=Data(:,I_Meas(1),I_Hem,I_ROIs{n}); dataX=dataX(:,:);
        dataY=Data(:,I_Meas(2),I_Hem,I_ROIs{n}); dataY=dataY(:,:);
        for n1=1:size(dataY,2), dataY(:,n1)=dataY(:,n1) - [ones(size(dataX,1),1) dataX(:,n1)] * ([ones(size(dataX,1),1) dataX(:,n1)]\dataY(:,n1)); end
        data=dataY;
    end
    data=data(:,:,:);
    valid=all(all(~isnan(data),2),3)&all(~isnan(Design),2);                % valid data (NaN represents missing data)
    [h,F(n),P(n),Dof{n},Stats{n}] = conn_glm(Design(valid,:), data(valid,:), Contr); % evalutes GLM
    %     dataSave = [dataSave data(valid,:)];
    if isequal(Stats{n},'T'), P(n)=2*min(P(n),1-P(n)); end       % forces two-sided
end

P_fdr=nan(size(P));
P_fdr(1:Nrois)=conn_fdr(P(1:Nrois));                                        % FDR-correction across lumped-ROIs
for n=1:Nrois %for each ROI (+1 is for all rois together)
    descr{n}=sprintf('%s : %s(%s) = %.2f, p-unc = %.3f, p-FDR = %.3f',sprintf('%s ',uname{I_ROIs{n}}),Stats{n},mat2str(Dof{n}),F(n),P(n), P_fdr(n));
end
n=Nrois+1; descr{n}=sprintf('all-ROIs average : %c(%s) = %.2f, p = %.3f',Stats{n},mat2str(Dof{n}),F(n),P(n));

if ~nargout
    out=[];
    [nill,idx]=sort(P);
    fprintf('All stats:\n');
    for n=1:numel(P)
        if idx(n)>Nrois, fprintf('  all-ROIs average, %s(%s)=%f, p-unc=%f\n',Stats{idx(n)},mat2str(Dof{idx(n)}),F(idx(n)),P(idx(n)));
        else fprintf('  ROI #%d (%s), %s(%s)=%f, p-unc=%f, p-FDR=%f\n',idx(n),sprintf('%s ',uname{I_ROIs{idx(n)}}),Stats{idx(n)},mat2str(Dof{idx(n)}),F(idx(n)),P(idx(n)),P_fdr(idx(n)));
        end
    end
    idx=find(P_fdr<=.05);                                    % find significant results
    if isempty(idx), fprintf('No significant results\n');
    else
        fprintf('%d significant results\n',numel(idx));
        for n=1:numel(idx)
            if idx(n)>Nrois, fprintf('  all-ROIs average, %s(%s)=%f, p-unc=%f\n',Stats{idx(n)},mat2str(Dof{idx(n)}),F(idx(n)),P(idx(n)));
            else fprintf('  ROI #%d (%s), %s(%s)=%f, p-unc=%f, p-FDR=%f\n',idx(n),sprintf('%s ',uname{I_ROIs{idx(n)}}),Stats{idx(n)},mat2str(Dof{idx(n)}),F(idx(n)),P(idx(n)),P_fdr(idx(n)));
            end
        end
    end
else
    idx=find(P_fdr(1:Nrois)<=.05);
    out=struct(...
        'ROIs',{uname},...
        'measures',{umeas},...
        'hemispheres',{uhemi},...
        'covariates',{COV_name},...
        'ROI_data',Data,...
        'COV_data',Covariates,...
        'Design',Design,...
        'Contrast',Contr,...
        'sign_ROIs', {uname(idx)},...
        'F',        F(1:Nrois), ...
        'dof',      {Dof(1:Nrois)},...
        'p',        P(1:Nrois),...
        'pfdr',     P_fdr(1:Nrois),...
        'desc',     {descr(1:Nrois)},...
        'combined_F',        F(Nrois+1), ...
        'combined_dof',      Dof{Nrois+1},...
        'combined_p',        P(Nrois+1),...
        'combined_desc',     descr{Nrois+1});
end
