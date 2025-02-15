USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRPRungTemplateImport
	CreatedBy: Larry Dugger
	Date: 2015-07-16
	Descr: This procedure populates the risk processing structure
		REMEMBER THESE LADDERS ARE 'BUILDING BLOCKS', IF YOU DON WANT TO OVERWRITE THEN
		MAINTAIN UNIQUE COLLECTION NAMES!
		It accesses an Excel template which has been pre-imported
		Converted to a format easier to implement into the binary tree structure
		represented by [riskprocessing].[LadderDBProcessXref]
		It currently depends on the following tables and relationships being
		pre-populated:
			 [riskprocessing].[RP]
			,[riskprocessing].[Ladder]
			,[riskprocessing].[LadderTop]
			,[riskprocessing].[DBProcess]
			,[riskprocessing].[ParameterType]
			,[riskprocessing].[Parameter]
		Once executed it will populate the following tables:
			 [riskprocessing].[LadderDBProcessXref]
			,[riskprocessing].[LadderDBProcessParameterXref]
			,[riskprocessing].[DBProcessParameterXref]
			,[riskprocessing].[ParameterValue]
			,[riskprocessing].[ParameterValueXref]
	Tables: [dbo].[BulkRPRung]
		,[common].[vwLadderDBProcessParameterXref]
		,[riskprocessing].[LadderDBProcessXref]
	Procedures: [riskprocessing].[uspLadderSelectOut]
		,[riskprocessing].[uspDBProcessSelect2Out]
		,[riskprocessing].[uspLadderDBProcessXrefInsertOut]
		,[riskprocessing].[uspLadderDBProcessParameterXrefInsertOut]
	Functions: [riskprocessing].[ufnMultipleParameters]
		,[riskprocessing].[ufnDBProcessParameterValueXrefs]
	History:
		2015-07-16 - LBD - Created using new template structure 
		2016-03-16 - LBD - Modified, removed use of OrgXref and Dimension,
			automatically replace LadderTop If it already exists...
		2016-09-30 - LBD - Modified, added CollectionName to comparison when performing
			multi-node association with parents
		2017-02-08 - LBD - Modified, removed use of [common].[ExitLevel], 
			[common].[Precedence], and [common].[LadderTrigger] tables and fields
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspRPRungTemplateImport]
AS
BEGIN
	SET NOCOUNT ON
	DECLARE @RPErrors table(
		Id int identity(1,1)
		,ErrorText nvarchar(255)
	);
	DECLARE @RPBinaryTree table(
		NodeId int identity(1,1)
		,ParentNodeId int
		,ParentSuccess nvarchar(3)
		,BulkRPRungIdYes int
		,BulkRPRungIdNo int
		,RPName nvarchar(50)
		--,PrecedenceId int
		,CollectionName nvarchar(100)
		--,LadderExitLevelId int
		--,LadderTriggerId int
		,LadderCode nvarchar(25)
		,Process nvarchar(50)
		,ProcessSyn nvarchar(50)
		,Success nvarchar(3)
		,SuccessProcess nvarchar(50)
		,SuccessProcessSyn nvarchar(50)
		,ContinueProcess nvarchar(50)
		,ContinueProcessSyn nvarchar(50)
		,Param1 nvarchar(512)
		,Param2 nvarchar(512)
		,Param3 nvarchar(512)
		,Param4 nvarchar(512)
		,Param5 nvarchar(512)
		,ExitLevel nvarchar(512)
		,Processed int
		,LadderDBProcessXrefid int
		,LadderId int
		,DBProcessId int
		,DBProcessSuccessValue nvarchar(512)
		,DBProcessSuccessLDBPXId int
		,DBProcessContinueLDBPXId int
		); 
	DECLARE @nvUserName nvarchar(100) = 'System'
		,@iStatusFlag int = 1
		,@iBulkRPRungId int
		,@iParentNodeId int
		,@nvRPName nvarchar(50)
		,@nvCollectionName nvarchar(100)
		,@nvLadderCode nvarchar(25)
		,@nvProcessName nvarchar(50)
		,@nvProcessNameSyn nvarchar(50)
		,@nvSuccess nvarchar(3)
		,@nvSuccessProcess nvarchar(50)
		,@nvSuccessProcessSyn nvarchar(50)
		,@nvContinueProcess nvarchar(50)
		,@nvContinueProcessSyn nvarchar(50)
		,@nvParam1 nvarchar(512)
		,@nvParam2 nvarchar(512)
		,@nvParam3 nvarchar(512)
		,@nvParam4 nvarchar(512)
		,@nvParam5 nvarchar(512)
		,@nvExitLevel nvarchar(512)
		,@iExitLevelId int
		,@iNodeId int
		,@nvParentSuccess nvarchar(3)
		,@iCnt int = 0
		,@nvProcess nvarchar(50)
		,@nvProcessSyn nvarchar(50)
		,@iProcessed int = -1
		,@iLadderId int
		,@iDBProcessId int
		,@iDBProcessSuccessId int
		,@iDBProcessContinueId int
		,@nvSuccessValue nvarchar(512)
		,@iLadderDBProcessXrefId int
		,@nvTitle nvarchar(255)
		,@nvDBProcessSuccessValue nvarchar(512)
		,@iDBProcessSuccessLDBPXId int
		,@iDBProcessContinueLDBPXId int
		,@iDBProcessParameterXrefId int
		,@iParameterId int
		,@iParameterValueId int
		,@iParameterValueXrefId int
		,@iLadderDBProcessParameterXrefId int
		,@iRPId int
		,@iOrgId int
		,@iOrgXrefId int
		--,@iPrecedenceId int
		--,@iLadderExitLevelId int
		--,@iLadderTriggerId int = 0
		,@iLadderTopId int
		,@bMultiParam bit
		,@iParam1Id int
		,@iParam2Id int
		,@iParam3Id int
		,@iParam4Id int
		,@iParam5Id int
		,@iResultId int
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName sysname;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	SELECT @iParam1Id = ParameterId from [riskprocessing].[Parameter] where Code = 'Param1';
	SELECT @iParam2Id = ParameterId from [riskprocessing].[Parameter] where Code = 'Param2';
	SELECT @iParam3Id = ParameterId from [riskprocessing].[Parameter] where Code = 'Param3';
	SELECT @iParam4Id = ParameterId from [riskprocessing].[Parameter] where Code = 'Param4';
	SELECT @iParam5Id = ParameterId from [riskprocessing].[Parameter] where Code = 'Param5';
	SELECT @iExitLevelId = ParameterId from [riskprocessing].[Parameter] where Code = 'ExitLevel';
	SELECT @iResultId = ParameterId from [riskprocessing].[Parameter] where Code = 'Result';
	--Translate Template  
	BEGIN TRANSACTION
	BEGIN TRY
		DECLARE csr_Translate CURSOR FOR
		SELECT BulkRPRungId
			,RPName
--			,PrecedenceId
			,LadderCollectionName
--			,e.ExitLevelId
--			,l.LadderTriggerId
			,LadderCode
			,ProcessName
			,CASE WHEN charindex('#',ProcessName) = 0 THEN '' ELSE SubString(ProcessName,1,CASE WHEN charindex('#',ProcessName) = 0 THEN ProcessName ELSE charindex('#',ProcessName)-1 END)  END 
			,Success
			,SuccessProcess
			,CASE WHEN charindex('#',SuccessProcess) = 0 THEN '' ELSE SubString(SuccessProcess,1,CASE WHEN charindex('#',SuccessProcess) = 0 THEN ProcessName ELSE charindex('#',SuccessProcess)-1 END)  END
			,ContinueProcess
			,CASE WHEN charindex('#',ContinueProcess) = 0 THEN '' ELSE SubString(ContinueProcess,1,CASE WHEN charindex('#',ContinueProcess) = 0 THEN ProcessName ELSE charindex('#',ContinueProcess)-1 END)  END
			,Param1
			,Param2
			,Param3
			,Param4
			,Param5
			,ExitLevel
		FROM [dbo].[BulkRPRung] b
		--INNER JOIN [common].[Precedence] p on b.Precedence = p.Precedence
		--INNER JOIN [common].[ExitLevel] e on b.LadderExitLevel = e.Code
		--INNER JOIN [common].[LadderTrigger] l on b.LadderTrigger = l.Name
		WHERE Processed = 0
		ORDER BY BulkRPRungId;
		OPEN csr_Translate;
		--FETCH csr_Translate INTO @iBulkRPRungId,@nvRPName,@iPrecedenceId,@nvCollectionName,@iLadderExitLevelId,@iLadderTriggerId,@nvLadderCode,@nvProcessName,
		--	@nvProcessNameSyn,@nvSuccess,@nvSuccessProcess,@nvSuccessProcessSyn,@nvContinueProcess,@nvContinueProcessSyn,@nvParam1,@nvParam2,@nvParam3,@nvParam4,@nvParam5,@nvExitLevel;
		FETCH csr_Translate INTO @iBulkRPRungId,@nvRPName,@nvCollectionName,@nvLadderCode,@nvProcessName,@nvProcessNameSyn,@nvSuccess,@nvSuccessProcess,
			@nvSuccessProcessSyn,@nvContinueProcess,@nvContinueProcessSyn,@nvParam1,@nvParam2,@nvParam3,@nvParam4,@nvParam5,@nvExitLevel;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			--NEW Ladder set node id to 0, establish LadderTop
			IF NOT EXISTS (SELECT 'X' FROM @RPBinaryTree 
						WHERE RPName = @nvRPName
									--AND PrecedenceId = @iPrecedenceId
									AND CollectionName = @nvCollectionName
									--AND LadderExitLevelId = @iLadderExitLevelId
									--AND LadderTriggerId = @iLadderTriggerId
									AND LadderCode = @nvLadderCode)
			SET @iNodeId = 0;
			IF NOT EXISTS (SELECT 'X' FROM @RPBinaryTree 
						WHERE RPName = @nvRPName
									--AND PrecedenceId = @iPrecedenceId
									AND CollectionName = @nvCollectionName
									--AND LadderExitLevelId = @iLadderExitLevelId
									--AND LadderTriggerId = @iLadderTriggerId
									AND LadderCode = @nvLadderCode 
							AND Process = @nvProcessName)
			BEGIN 
			--DOES Parent exists, if so set what success value causes this path to be executed?
			SELECT @iNodeId = NodeId
				,@nvParentSuccess=CASE WHEN SuccessProcess = @nvProcessName THEN
											CASE WHEN Success = 'Yes' THEN 'Yes' ELSE 'No' END 
										WHEN ContinueProcess = @nvProcessName THEN
											CASE WHEN Success = 'Yes' THEN 'No' ELSE 'Yes' END 
									END
			FROM @RPBinaryTree
			WHERE RPName = @nvRPName
					--AND PrecedenceId = @iPrecedenceId
					AND CollectionName = @nvCollectionName
					--AND LadderExitLevelId = @iLadderExitLevelId
					AND LadderCode = @nvLadderCode
				AND (SuccessProcess = @nvProcessName 
						OR ContinueProcess = @nvProcessName);
				--INSERT this node
			--INSERT INTO @RPBinaryTree(ParentNodeId,ParentSuccess,BulkRPRungIdYes,RPName,PrecedenceId,CollectionName,LadderExitLevelId,LadderTriggerId,
			--		LadderCode,Process,ProcessSyn,Success,SuccessProcess,SuccessProcessSyn,ContinueProcess,ContinueProcessSyn,Processed,Param1,Param2,Param3,Param4,Param5,ExitLevel)
			--SELECT @iNodeId,@nvParentSuccess,@iBulkRPRungId,@nvRPName,@iPrecedenceId,@nvCollectionName,@iLadderExitLevelId,@iLadderTriggerId,
			--		@nvLadderCode,@nvProcessName,@nvProcessNameSyn,@nvSuccess,@nvSuccessProcess,@nvSuccessProcessSyn,@nvContinueProcess,@nvContinueProcessSyn,@iProcessed,@nvParam1,@nvParam2,@nvParam3,@nvParam4,@nvParam5,@nvExitLevel;
			INSERT INTO @RPBinaryTree(ParentNodeId,ParentSuccess,BulkRPRungIdYes,RPName,CollectionName,LadderCode,Process,ProcessSyn,Success
				,SuccessProcess,SuccessProcessSyn,ContinueProcess,ContinueProcessSyn,Processed,Param1,Param2,Param3,Param4,Param5,ExitLevel)
			SELECT @iNodeId,@nvParentSuccess,@iBulkRPRungId,@nvRPName,@nvCollectionName,@nvLadderCode,@nvProcessName,@nvProcessNameSyn,@nvSuccess
				,@nvSuccessProcess,@nvSuccessProcessSyn,@nvContinueProcess,@nvContinueProcessSyn,@iProcessed,@nvParam1,@nvParam2,@nvParam3,@nvParam4,@nvParam5,@nvExitLevel;
			SET @iNodeId = SCOPE_IDENTITY();
			IF @nvParentSuccess IS NULL 
				SET @nvParentSuccess = @nvSuccess;
			END
			UPDATE [dbo].[BulkRPRung] set Processed = 1 WHERE BulkRPRungId = @iBulkRPRungId;
			--FETCH csr_Translate INTO @iBulkRPRungId,@nvRPName,@iPrecedenceId,@nvCollectionName,@iLadderExitLevelId,@iLadderTriggerId,@nvLadderCode,@nvProcessName
			--	,@nvProcessNameSyn,@nvSuccess,@nvSuccessProcess,@nvSuccessProcessSyn,@nvContinueProcess,@nvContinueProcessSyn,@nvParam1,@nvParam2,@nvParam3,@nvParam4,@nvParam5,@nvExitLevel;
			FETCH csr_Translate INTO @iBulkRPRungId,@nvRPName,@nvCollectionName,@nvLadderCode,@nvProcessName,@nvProcessNameSyn,@nvSuccess
				,@nvSuccessProcess,@nvSuccessProcessSyn,@nvContinueProcess,@nvContinueProcessSyn,@nvParam1,@nvParam2,@nvParam3,@nvParam4,@nvParam5,@nvExitLevel;
			SET @nvParentSuccess = NULL;
			SET @iNodeId = NULL;
		END
		CLOSE csr_Translate;
		DEALLOCATE csr_Translate;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		INSERT INTO @RPErrors(ErrorText)
		SELECT 'Translate Template Problem ErrorDetailId='+CONVERT(NVARCHAR(10),@iErrorDetailId);
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
		COMMIT TRANSACTION;
	--HERE IS WHERE WE MIGRATE the Binary Tree to the system
	--LadderTop Creation
	--LadderDBProcessXref Creation
	BEGIN TRANSACTION
	BEGIN TRY
		DECLARE csr_BuildTree CURSOR FOR
		--SELECT NodeId,ParentNodeId,ParentSuccess,RPName,PrecedenceId,CollectionName,LadderExitLevelId,LadderTriggerId,LadderCode,
		--	Process,ProcessSyn,Success,SuccessProcess,SuccessProcessSyn,ContinueProcess,ContinueProcessSyn,Param1,Param2,Param3,Param4,Param5,ExitLevel,Processed
		SELECT NodeId,ParentNodeId,ParentSuccess,RPName,CollectionName,LadderCode,Process,ProcessSyn,Success
			,SuccessProcess,SuccessProcessSyn,ContinueProcess,ContinueProcessSyn,Param1,Param2,Param3,Param4,Param5,ExitLevel,Processed
		FROM @RPBinaryTree
		ORDER BY LadderCode,ParentNodeId,NodeId;
		OPEN csr_BuildTree;
		--FETCH csr_BuildTree INTO @iNodeId,@iParentNodeId,@nvParentSuccess,@nvRPName,@iPrecedenceId,@nvCollectionName,@iLadderExitLevelId,@iLadderTriggerId,@nvLadderCode,
		--	@nvProcess,@nvProcessSyn,@nvSuccess,@nvSuccessProcess,@nvSuccessProcessSyn,@nvContinueProcess,@nvContinueProcessSyn,@nvParam1,@nvParam2,@nvParam3,@nvParam4,@nvParam5,@nvExitLevel,@iProcessed;
		FETCH csr_BuildTree INTO @iNodeId,@iParentNodeId,@nvParentSuccess,@nvRPName,@nvCollectionName,@nvLadderCode,@nvProcess,@nvProcessSyn,@nvSuccess
			,@nvSuccessProcess,@nvSuccessProcessSyn,@nvContinueProcess,@nvContinueProcessSyn,@nvParam1,@nvParam2,@nvParam3,@nvParam4,@nvParam5,@nvExitLevel,@iProcessed;
		WHILE @@FETCH_STATUS = 0
		BEGIN 
			SET @iLadderId = 0;
			SET @iDBProcessId = 0;
			SET @iLadderDBProcessXrefId = 0;
			--GET Ladder
			EXECUTE [riskprocessing].[uspLadderSelectOut] @pnvCode = @nvLadderCode, @piLadderId = @iLadderId OUTPUT;
			IF @iLadderId <> 0
			BEGIN
			--GET DBProcess, we look at the ProcessSyn, since it is tha actual DBProcessName within the system
				IF ISNULL(@nvProcessSyn,'') = ''
					EXECUTE [riskprocessing].[uspDBProcessSelect2Out] @pnvName=@nvProcess, @piDBProcessId = @iDBProcessId OUTPUT;
				ELSE
					EXECUTE [riskprocessing].[uspDBProcessSelect2Out] @pnvName=@nvProcessSyn, @piDBProcessId = @iDBProcessId OUTPUT;
			IF @iDBProcessId <> 0
			BEGIN
				SET @nvSuccessValue = CASE WHEN @nvSuccess = 'Yes' THEN 1 WHEN @nvSuccess= 'No' THEN 0 ELSE NULL END
					IF ISNULL(@nvProcessSyn,'') = ''
						SET @nvTitle = 'Execute '+@nvProcess 
					ELSE
						SET @nvTitle = 'Execute '+@nvProcessSyn 
				--FIRST we insert each record   
				IF @iLadderDBProcessXrefId = 0
					EXECUTE [riskprocessing].[uspLadderDBProcessXrefInsertOut]
						@pnvTitle = @nvTitle
						,@piLadderId = @iLadderId
						,@piDBProcessId = @iDBProcessId
						,@pnvDBProcessSuccessValue = @nvSuccessValue
						,@piDBProcessSuccessLDBPXId = 0
						,@piDBProcessContinueLDBPXId = 0
						,@piStatusFlag = @iStatusFlag
						,@pnvUserName = @nvUserName
						,@piLadderDBProcessXrefId = @iLadderDBProcessXrefId OUTPUT;
				IF @iLadderDBProcessXrefId > 0
					BEGIN
					UPDATE @RPBinaryTree
						SET LadderDBProcessXrefid =  @iLadderDBProcessXrefId
						,DBProcessSuccessLDBPXId = 0
						,DBProcessContinueLDBPXId = 0
						,LadderId = @iLadderId
						,DBProcessId = @iDBProcessId
						,DBProcessSuccessValue = @nvSuccessValue
						,Processed = 0
					WHERE NodeId = @iNodeId;
						--IS this the Start of a path? If so insert/update a LadderTop.
						IF @iParentNodeId = 0
						BEGIN
							SELECT @iRPId = RPId
							FROM [riskprocessing].[RP]
							WHERE Code = @nvRPName;
							SET @iLadderTopId = 0;
							EXECUTE [riskprocessing].[uspLadderTopUpsertOut]
								 @piRPId = @iRPId
								,@piLadderDBProcessXrefId = @iLadderDBProcessXrefId
								,@pnvCollectionName = @nvCollectionName
								,@piStatusFlag = @iStatusFlag
								,@pnvUserName = @nvUserName
								,@piLadderTopId = @iLadderTopId OUTPUT;
							IF @iLadderTopId < 1
								INSERT INTO @RPErrors(ErrorText)
								SELECT 'Error upserting LadderTop for RP '+ISNULL(@nvRPName,'');
						END
					END
				ELSE
					INSERT INTO @RPErrors(ErrorText)
					SELECT 'Error inserting DBProcess/LadderCode '+ISNULL(@nvProcess,'')+'/'+ISNULL(@nvLadderCode,'');
			END
			ELSE
				INSERT INTO @RPErrors(ErrorText)
				SELECT 'Error referencing DBProcess '+ISNULL(@nvProcess,'');
			END
			ELSE
			INSERT INTO @RPErrors(ErrorText)
			SELECT 'Error referencing LadderCode '+ISNULL(@nvLadderCode,'');
			--FETCH csr_BuildTree INTO @iNodeId,@iParentNodeId,@nvParentSuccess,@nvRPName,@iPrecedenceId,@nvCollectionName,@iLadderExitLevelId,@iLadderTriggerId,@nvLadderCode,
			--	@nvProcess,@nvProcessSyn,@nvSuccess,@nvSuccessProcess,@nvSuccessProcessSyn,@nvContinueProcess,@nvContinueProcessSyn,@nvParam1,@nvParam2,@nvParam3,@nvParam4,@nvParam5,@nvExitLevel,@iProcessed;
			FETCH csr_BuildTree INTO @iNodeId,@iParentNodeId,@nvParentSuccess,@nvRPName,@nvCollectionName,@nvLadderCode,@nvProcess,@nvProcessSyn,@nvSuccess
				,@nvSuccessProcess,@nvSuccessProcessSyn,@nvContinueProcess,@nvContinueProcessSyn,@nvParam1,@nvParam2,@nvParam3,@nvParam4,@nvParam5,@nvExitLevel,@iProcessed;
		END
		CLOSE csr_BuildTree;
		DEALLOCATE csr_BuildTree;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		INSERT INTO @RPErrors(ErrorText)
		SELECT 'LadderDBProcessXref Creation Problem ErrorDetailId='+CONVERT(NVARCHAR(10),@iErrorDetailId);
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
		COMMIT TRANSACTION;
	--SET LadderDBProcessXref Success and Continue, being cognizant of the Success path i.e. ParentSuccess
	BEGIN TRANSACTION
	BEGIN TRY
		--LOAD the xref info just established into the proper slots
		UPDATE bt
			SET DBProcessSuccessLDBPXId = btS.LadderDBProcessXrefId
		FROM @RPBinaryTree bt
		INNER JOIN @RPBinaryTree bts ON bt.NodeId = bts.ParentNodeId
									AND bts.ParentSuccess = 'Yes'
		WHERE bt.Success = 'Yes';
		UPDATE bt
			SET DBProcessContinueLDBPXId = btc.LadderDBProcessXrefId
		FROM @RPBinaryTree bt
		INNER JOIN @RPBinaryTree btc ON bt.NodeId = btc.ParentNodeId
									AND btc.ParentSuccess = 'No'
		WHERE bt.Success = 'Yes';
		UPDATE bt
			SET DBProcessContinueLDBPXId = btS.LadderDBProcessXrefId
		FROM @RPBinaryTree bt
		INNER JOIN @RPBinaryTree bts ON bt.NodeId = bts.ParentNodeId
									AND bts.ParentSuccess = 'Yes'
		WHERE bt.Success = 'No';
		UPDATE bt
			SET DBProcessSuccessLDBPXId = btc.LadderDBProcessXrefId
		FROM @RPBinaryTree bt
		INNER JOIN @RPBinaryTree btc ON bt.NodeId = btc.ParentNodeId
									AND btc.ParentSuccess = 'No'
		WHERE bt.Success = 'No';
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		INSERT INTO @RPErrors(ErrorText)
		SELECT 'Set LadderDBProcessXref Success and Continue Problem ErrorDetailId='+CONVERT(NVARCHAR(10),@iErrorDetailId);
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
		COMMIT TRANSACTION;
	--THIS allows us to associate multiple nodes with the same parent node
	BEGIN TRANSACTION
	BEGIN TRY
		IF EXISTS (SELECT 'X'
					FROM @RPBinaryTree
					WHERE DBProcessSuccessLDBPXId = 0 
						AND [riskprocessing].[ufnMultipleParameters](Process) <> 1)
			UPDATE r
			SET DBProcessSuccessLDBPXId = r2.LadderDBProcessXrefId
			FROM @RPBinaryTree r
			INNER JOIN @RPBinaryTree r2 ON r.CollectionName = r2.CollectionName	--2016-09-30
											AND r.LadderCode = r2.LadderCode
											AND r.SuccessProcess = r2.Process
			WHERE r.DBProcessSuccessLDBPXId = 0;
			--AND [riskprocessing].[ufnMultipleParameters](r.Process) <> 1;
		IF EXISTS (SELECT 'X'
				FROM @RPBinaryTree
				WHERE DBProcessContinueLDBPXId = 0 
					AND [riskprocessing].[ufnMultipleParameters](Process) <> 1)
			UPDATE r
				SET DBProcessContinueLDBPXId = r2.LadderDBProcessXrefId
			FROM @RPBinaryTree r
			INNER JOIN @RPBinaryTree r2 ON  r.CollectionName = r2.CollectionName	--2016-09-30
											AND r.LadderCode = r2.LadderCode
											AND r.ContinueProcess = r2.Process
			WHERE r.DBProcessContinueLDBPXId = 0;
			--AND [riskprocessing].[ufnMultipleParameters](r.Process) <> 1;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		INSERT INTO @RPErrors(ErrorText)
		SELECT 'Set LadderDBProcessXref Success and Continue2 Problem ErrorDetailId='+CONVERT(NVARCHAR(10),@iErrorDetailId);
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
		COMMIT TRANSACTION;
	--NOW Update the real binary tree table
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE ldbpx
		SET DBProcessSuccessLDBPXId = bt.DBProcessSuccessLDBPXId
			,DBProcessContinueLDBPXId = bt.DBProcessContinueLDBPXId
		FROM [riskprocessing].[LadderDBProcessXref] ldbpx
		INNER JOIN @RPBinaryTree bt ON ldbpx.LadderDBProcessXrefid = bt.LadderDBProcessXrefid;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		INSERT INTO @RPErrors(ErrorText)
		SELECT 'Set LadderDBProcessXref Update Problem ErrorDetailId='+CONVERT(NVARCHAR(10),@iErrorDetailId);
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
		COMMIT TRANSACTION;
	--ASSOCIATE each DBProcess with 'its' external parameter values
	BEGIN TRANSACTION
	BEGIN TRY
		DECLARE csr_CompleteTree CURSOR FOR
		SELECT NodeId,ParentNodeId,ParentSuccess,LadderCode,Process,ProcessSyn,Success,SuccessProcess,ContinueProcess,DBProcessSuccessValue,
			LadderDBProcessXrefId,DBProcessSuccessLDBPXId,DBProcessContinueLDBPXId,Param1,Param2,Param3,Param4,Param5,ExitLevel,Processed 
		FROM @RPBinaryTree 
		ORDER BY LadderCode,ParentNodeId,NodeId;
		OPEN csr_CompleteTree;
		FETCH csr_CompleteTree INTO @iNodeId,@iParentNodeId,@nvParentSuccess,@nvLadderCode,@nvProcess,@nvProcessSyn,@nvSuccess,@nvSuccessProcess,@nvContinueProcess,@nvDBProcessSuccessValue,
			@iLadderDBProcessXrefId,@iDBProcessSuccessLDBPXId,@iDBProcessContinueLDBPXId,@nvParam1,@nvParam2,@nvParam3,@nvParam4,@nvParam5,@nvExitLevel,@iProcessed;
		WHILE @@FETCH_STATUS = 0
		BEGIN 
			--Start with the current record, remember DBProcess, parameter, and DBProcessParameterXref are defined by Database team
			--IF NOT EXISTS (SELECT 'X'
			--			FROM [common].[vwLadderDBProcessParameterXref] x
			--			INNER JOIN [riskprocessing].[LadderDBProcessXref] x2 ON x.LadderDBProcessXrefId = x2.LadderDBProcessXrefId
			--			WHERE x.LadderDBProcessXrefId = @iLadderDBProcessXrefId)
			IF NOT EXISTS (SELECT 'X'
						FROM [riskprocessing].[Ladder] c WITH (NOLOCK)
						INNER JOIN [riskprocessing].[LadderDBProcessXref] ldbpx WITH (NOLOCK) ON c.LadderId = ldbpx.LadderId
						INNER JOIN [riskprocessing].[DBProcess] dbp WITH (NOLOCK) ON ldbpx.DBProcessId = dbp.DBProcessId
						INNER JOIN [riskprocessing].[LadderDBProcessParameterXref] ldbppx WITH (NOLOCK) ON ldbpx.LadderDBProcessXrefId = ldbppx.LadderDBProcessXrefId
						INNER JOIN [riskprocessing].[DBProcessParameterXref] dbppx WITH (NOLOCK) ON ldbppx.DBProcessParameterXrefId = dbppx.DBProcessParameterXrefId
						INNER JOIN [riskprocessing].[Parameter] p WITH (NOLOCK) ON dbppx.ParameterId = p.ParameterId
						INNER JOIN [riskprocessing].[ParameterValueXref] pvx WITH (NOLOCK) ON ldbppx.ParameterValueXrefId = pvx.ParameterValueXrefId
						INNER JOIN [riskprocessing].[ParameterValue] pv WITH (NOLOCK) ON pvx.ParameterValueId = pv.ParameterValueId 
						INNER JOIN [riskprocessing].[ParameterType] pt WITH (NOLOCK) ON p.ParameterTypeId = pt.ParameterTypeId
						WHERE ldbpx.LadderDBProcessXrefId = @iLadderDBProcessXrefId)
			BEGIN 
				--IS this Process multiparametered?
				SET @bMultiParam=0;
				SET @bMultiParam=[riskprocessing].[ufnMultipleParameters](CASE WHEN ISNULL(@nvProcessSyn,'')='' THEN @nvProcess ELSE @nvProcessSyn END);
				--We must define this instance, by setting Parameter values, all are Position to Value specific
				--EVERY DBProcess has a Result
				SET @iLadderDBProcessParameterXrefId = 0;
				SET @iDBProcessParameterXrefId = 0;
				SET @iParameterValueXrefId = 0;
				SELECT @iDBProcessParameterXrefId = DBProcessParameterXrefId
					,@iParameterValueXrefId = ParameterValueXrefId
				FROM [riskprocessing].[ufnDBProcessParameterValueXrefs](CASE WHEN ISNULL(@nvProcessSyn,'')='' THEN @nvProcess ELSE @nvProcessSyn END)
				WHERE Code = 'Result'
					AND Value = 'Result';
				SELECT @iDBProcessId = DBProcessId FROM [riskprocessing].[DBProcess] WHERE Name = CASE WHEN ISNULL(@nvProcessSyn,'')='' THEN @nvProcess ELSE @nvProcessSyn END;
				IF @iDBProcessParameterXrefId = 0
				BEGIN
					EXECUTE [riskprocessing].[uspDBProcessParameterXrefInsertOut] 
						 @piDBProcessId=@iDBProcessId
						,@piParameterId=@iResultId
						,@piStatusFlag=1
						,@pnvUserName = @nvUserName
						,@piDBProcessParameterXrefId=@iDBProcessParameterXrefId output;
				END
				IF @iParameterValueXrefId = 0
				BEGIN
					EXECUTE [riskprocessing].[uspParameterValueInsertOut] @pnvValue='Result',@piStatusFlag=1,@pnvUserName = @nvUserName,@piParameterValueId=@iParameterValueId output;
					EXECUTE [riskprocessing].[uspParameterValueXrefInsertOut] @piParameterId=@iResultId,@piParameterValueId=@iParameterValueId,@piStatusFlag=1,@pnvUserName = @nvUserName,@piParameterValueXrefId=@iParameterValueXrefId output;
				END
				EXECUTE [riskprocessing].[uspLadderDBProcessParameterXrefInsertOut]
					 @piLadderDBProcessXrefId = @iLadderDBProcessXrefId
					,@piDBProcessParameterXrefId = @iDBProcessParameterXrefId
					,@piParameterValueXrefId = @iParameterValueXrefId                          
					,@piStatusFlag = @iStatusFlag
					,@pnvUserName = @nvUserName
					,@piLadderDBProcessParameterXrefId = @iLadderDBProcessParameterXrefId OUTPUT;
				--EVERY DBProcess has an ExitLevel
				SET @iLadderDBProcessParameterXrefId = 0;
				SET @iDBProcessParameterXrefId = 0;
				SET @iParameterValueXrefId = 0;
				SELECT @iDBProcessParameterXrefId = DBProcessParameterXrefId
					,@iParameterValueXrefId = ParameterValueXrefId
				FROM [riskprocessing].[ufnDBProcessParameterValueXrefs](CASE WHEN ISNULL(@nvProcessSyn,'')='' THEN @nvProcess ELSE @nvProcessSyn END)
				WHERE Code = 'ExitLevel'
					AND Value = @nvExitLevel;
				SELECT @iDBProcessId = DBProcessId FROM [riskprocessing].[DBProcess] WHERE Name = CASE WHEN ISNULL(@nvProcessSyn,'')='' THEN @nvProcess ELSE @nvProcessSyn END;
				IF @iDBProcessParameterXrefId = 0
				BEGIN
					EXECUTE [riskprocessing].[uspDBProcessParameterXrefInsertOut] 
						 @piDBProcessId=@iDBProcessId
						,@piParameterId=@iExitLevelId
						,@piStatusFlag=1
						,@pnvUserName = @nvUserName
						,@piDBProcessParameterXrefId=@iDBProcessParameterXrefId output;
				END
				IF @iParameterValueXrefId = 0
				BEGIN
					EXECUTE [riskprocessing].[uspParameterValueInsertOut] @pnvValue=@nvExitLevel,@piStatusFlag=1,@pnvUserName = @nvUserName,@piParameterValueId=@iParameterValueId output;
					EXECUTE [riskprocessing].[uspParameterValueXrefInsertOut] @piParameterId=@iExitLevelId,@piParameterValueId=@iParameterValueId,@piStatusFlag=1,@pnvUserName = @nvUserName,@piParameterValueXrefId=@iParameterValueXrefId output;
				END
				EXECUTE [riskprocessing].[uspLadderDBProcessParameterXrefInsertOut]
					 @piLadderDBProcessXrefId = @iLadderDBProcessXrefId  
					,@piDBProcessParameterXrefId = @iDBProcessParameterXrefId
					,@piParameterValueXrefId = @iParameterValueXrefId                          
					,@piStatusFlag = @iStatusFlag
					,@pnvUserName = @nvUserName
					,@piLadderDBProcessParameterXrefId = @iLadderDBProcessParameterXrefId OUTPUT;

				IF @iLadderDBProcessParameterXrefId > 0   
				BEGIN
					IF @bMultiParam = 1
						AND ISNULL(@nvParam1,'') <> ''
					BEGIN
						SET @iLadderDBProcessParameterXrefId = 0;
						SET @iDBProcessParameterXrefId = 0;
						SET @iParameterValueXrefId = 0;
						SELECT @iDBProcessParameterXrefId = DBProcessParameterXrefId
							,@iParameterValueXrefId = ParameterValueXrefId
						FROM [riskprocessing].[ufnDBProcessParameterValueXrefs](CASE WHEN ISNULL(@nvProcessSyn,'')='' THEN @nvProcess ELSE @nvProcessSyn END)
						WHERE Code = 'Param1'
							AND Value = @nvParam1;
						IF @iDBProcessParameterXrefId = 0
						BEGIN
							EXECUTE [riskprocessing].[uspDBProcessParameterXrefInsertOut] 
								 @piDBProcessId=@iDBProcessId
								,@piParameterId=@iParam1Id
								,@piStatusFlag=1
								,@pnvUserName = @nvUserName
								,@piDBProcessParameterXrefId=@iDBProcessParameterXrefId output;
						END
						IF @iParameterValueXrefId = 0
						BEGIN
							EXECUTE [riskprocessing].[uspParameterValueInsertOut] @pnvValue=@nvParam1,@piStatusFlag=1,@pnvUserName = @nvUserName,@piParameterValueId=@iParameterValueId output;
							EXECUTE [riskprocessing].[uspParameterValueXrefInsertOut] @piParameterId=@iParam1Id,@piParameterValueId=@iParameterValueId,@piStatusFlag=1,@pnvUserName = @nvUserName,@piParameterValueXrefId=@iParameterValueXrefId output;
						END
						EXECUTE [riskprocessing].[uspLadderDBProcessParameterXrefInsertOut]
							 @piLadderDBProcessXrefId = @iLadderDBProcessXrefId  
							,@piDBProcessParameterXrefId = @iDBProcessParameterXrefId
							,@piParameterValueXrefId = @iParameterValueXrefId                          
							,@piStatusFlag = @iStatusFlag
							,@pnvUserName = @nvUserName
							,@piLadderDBProcessParameterXrefId = @iLadderDBProcessParameterXrefId OUTPUT;
						IF @iLadderDBProcessParameterXrefId > 0
							AND ISNULL(@nvParam2,'') <> ''
						BEGIN
							SET @iLadderDBProcessParameterXrefId = 0;
							SET @iDBProcessParameterXrefId = 0;
							SET @iParameterValueXrefId = 0;
							SELECT @iDBProcessParameterXrefId = DBProcessParameterXrefId
								,@iParameterValueXrefId = ParameterValueXrefId
							FROM [riskprocessing].[ufnDBProcessParameterValueXrefs](CASE WHEN ISNULL(@nvProcessSyn,'')='' THEN @nvProcess ELSE @nvProcessSyn END)
							WHERE Code = 'Param2'
								AND Value = @nvParam2;
							IF @iDBProcessParameterXrefId = 0
							BEGIN
								EXECUTE [riskprocessing].[uspDBProcessParameterXrefInsertOut] 
									 @piDBProcessId=@iDBProcessId
									,@piParameterId=@iParam2Id
									,@piStatusFlag=1
									,@pnvUserName = @nvUserName
									,@piDBProcessParameterXrefId=@iDBProcessParameterXrefId output;
							END
							IF @iParameterValueXrefId = 0
							BEGIN
								EXECUTE [riskprocessing].[uspParameterValueInsertOut] @pnvValue=@nvParam2,@piStatusFlag=1,@pnvUserName = @nvUserName,@piParameterValueId=@iParameterValueId output;
								EXECUTE [riskprocessing].[uspParameterValueXrefInsertOut] @piParameterId=@iParam2Id,@piParameterValueId=@iParameterValueId,@piStatusFlag=1,@pnvUserName = @nvUserName,@piParameterValueXrefId=@iParameterValueXrefId output;
							END
							EXECUTE [riskprocessing].[uspLadderDBProcessParameterXrefInsertOut]
								 @piLadderDBProcessXrefId = @iLadderDBProcessXrefId  
								,@piDBProcessParameterXrefId = @iDBProcessParameterXrefId
								,@piParameterValueXrefId = @iParameterValueXrefId                          
								,@piStatusFlag = @iStatusFlag
								,@pnvUserName = @nvUserName
								,@piLadderDBProcessParameterXrefId = @iLadderDBProcessParameterXrefId OUTPUT
							IF @iLadderDBProcessParameterXrefId > 0
								AND ISNULL(@nvParam3,'') <> ''
							BEGIN
								SET @iLadderDBProcessParameterXrefId = 0;
								SET @iDBProcessParameterXrefId = 0;
								SET @iParameterValueXrefId = 0;
								SELECT @iDBProcessParameterXrefId = DBProcessParameterXrefId
									,@iParameterValueXrefId = ParameterValueXrefId
								FROM [riskprocessing].[ufnDBProcessParameterValueXrefs](CASE WHEN ISNULL(@nvProcessSyn,'')='' THEN @nvProcess ELSE @nvProcessSyn END)
								WHERE Code = 'Param3'
									AND Value = @nvParam3;
								IF @iDBProcessParameterXrefId = 0
								BEGIN
									EXECUTE [riskprocessing].[uspDBProcessParameterXrefInsertOut] 
										 @piDBProcessId=@iDBProcessId
										,@piParameterId=@iParam3Id
										,@piStatusFlag=1
										,@pnvUserName = @nvUserName
										,@piDBProcessParameterXrefId=@iDBProcessParameterXrefId output;
								END
								IF @iParameterValueXrefId = 0
								BEGIN
									EXECUTE [riskprocessing].[uspParameterValueInsertOut] @pnvValue=@nvParam3,@piStatusFlag=1,@pnvUserName = @nvUserName,@piParameterValueId=@iParameterValueId output;
									EXECUTE [riskprocessing].[uspParameterValueXrefInsertOut] @piParameterId=@iParam3Id,@piParameterValueId=@iParameterValueId,@piStatusFlag=1,@pnvUserName = @nvUserName,@piParameterValueXrefId=@iParameterValueXrefId output;
								END
								EXECUTE [riskprocessing].[uspLadderDBProcessParameterXrefInsertOut]
									 @piLadderDBProcessXrefId = @iLadderDBProcessXrefId  
									,@piDBProcessParameterXrefId = @iDBProcessParameterXrefId
									,@piParameterValueXrefId = @iParameterValueXrefId                          
									,@piStatusFlag = @iStatusFlag
									,@pnvUserName = @nvUserName
									,@piLadderDBProcessParameterXrefId = @iLadderDBProcessParameterXrefId OUTPUT
								IF @iLadderDBProcessParameterXrefId > 0
									AND ISNULL(@nvParam4,'') <> ''
								BEGIN
									SET @iLadderDBProcessParameterXrefId = 0;
									SET @iDBProcessParameterXrefId = 0;
									SET @iParameterValueXrefId = 0;
									SELECT @iDBProcessParameterXrefId = DBProcessParameterXrefId
										,@iParameterValueXrefId = ParameterValueXrefId
									FROM [riskprocessing].[ufnDBProcessParameterValueXrefs](CASE WHEN ISNULL(@nvProcessSyn,'')='' THEN @nvProcess ELSE @nvProcessSyn END)
									WHERE Code = 'Param4'
										AND Value = @nvParam4;
									IF @iDBProcessParameterXrefId = 0
									BEGIN
										EXECUTE [riskprocessing].[uspDBProcessParameterXrefInsertOut] 
											 @piDBProcessId=@iDBProcessId
											,@piParameterId=@iParam4Id
											,@piStatusFlag=1
											,@pnvUserName = @nvUserName
											,@piDBProcessParameterXrefId=@iDBProcessParameterXrefId output;
									END
									IF @iParameterValueXrefId = 0
									BEGIN
										EXECUTE [riskprocessing].[uspParameterValueInsertOut] @pnvValue=@nvParam4,@piStatusFlag=1,@pnvUserName = @nvUserName,@piParameterValueId=@iParameterValueId output;
										EXECUTE [riskprocessing].[uspParameterValueXrefInsertOut] @piParameterId=@iParam4Id,@piParameterValueId=@iParameterValueId,@piStatusFlag=1,@pnvUserName = @nvUserName,@piParameterValueXrefId=@iParameterValueXrefId output;
									END
									EXECUTE [riskprocessing].[uspLadderDBProcessParameterXrefInsertOut]
										 @piLadderDBProcessXrefId = @iLadderDBProcessXrefId  
										,@piDBProcessParameterXrefId = @iDBProcessParameterXrefId
										,@piParameterValueXrefId = @iParameterValueXrefId                          
										,@piStatusFlag = @iStatusFlag
										,@pnvUserName = @nvUserName
										,@piLadderDBProcessParameterXrefId = @iLadderDBProcessParameterXrefId OUTPUT
									IF @iLadderDBProcessParameterXrefId > 0 
										AND ISNULL(@nvParam5,'') <> '' 
									BEGIN
										SET @iLadderDBProcessParameterXrefId = 0;
										SET @iDBProcessParameterXrefId = 0;
										SET @iParameterValueXrefId = 0;
										SELECT @iDBProcessParameterXrefId = DBProcessParameterXrefId
											,@iParameterValueXrefId = ParameterValueXrefId
										FROM [riskprocessing].[ufnDBProcessParameterValueXrefs](CASE WHEN ISNULL(@nvProcessSyn,'')='' THEN @nvProcess ELSE @nvProcessSyn END)
										WHERE  Code = 'Param5'
											AND Value = @nvParam5;
										IF @iDBProcessParameterXrefId = 0
										BEGIN
											EXECUTE [riskprocessing].[uspDBProcessParameterXrefInsertOut] 
												 @piDBProcessId=@iDBProcessId
												,@piParameterId=@iParam5Id
												,@piStatusFlag=1
												,@pnvUserName = @nvUserName
												,@piDBProcessParameterXrefId=@iDBProcessParameterXrefId output;
										END
										IF @iParameterValueXrefId = 0
										BEGIN
												EXECUTE [riskprocessing].[uspParameterValueInsertOut] @pnvValue=@nvParam5,@piStatusFlag=1,@pnvUserName = @nvUserName,@piParameterValueId=@iParameterValueId output;
												EXECUTE [riskprocessing].[uspParameterValueXrefInsertOut] @piParameterId=@iParam5Id,@piParameterValueId=@iParameterValueId,@piStatusFlag=1,@pnvUserName = @nvUserName,@piParameterValueXrefId=@iParameterValueXrefId output;
										END
										EXECUTE [riskprocessing].[uspLadderDBProcessParameterXrefInsertOut]
											 @piLadderDBProcessXrefId = @iLadderDBProcessXrefId  
											,@piDBProcessParameterXrefId = @iDBProcessParameterXrefId
											,@piParameterValueXrefId = @iParameterValueXrefId                          
											,@piStatusFlag = @iStatusFlag
											,@pnvUserName = @nvUserName
											,@piLadderDBProcessParameterXrefId = @iLadderDBProcessParameterXrefId OUTPUT
										IF @iLadderDBProcessParameterXrefId <= 0
											INSERT INTO @RPErrors(ErrorText)
											SELECT 'CDBPPX Insert Param5('+@nvParam5+'):'+ISNULL(@nvParam4,'')+', DBProcess/LadderCode '+ISNULL(@nvProcess,'')+'/'+ISNULL(@nvLadderCode,'');
									END
									ELSE IF ISNULL(@nvParam5,'') <> ''
										INSERT INTO @RPErrors(ErrorText)
										SELECT 'CDBPPX Insert Param4('+@nvParam4+'):'+ISNULL(@nvParam3,'')+', DBProcess/LadderCode '+ISNULL(@nvProcess,'')+'/'+ISNULL(@nvLadderCode,'');
								END
								ELSE IF ISNULL(@nvParam4,'') <> ''
									INSERT INTO @RPErrors(ErrorText)
									SELECT 'CDBPPX Insert Param3('+@nvParam3+'):'+ISNULL(@nvParam2,'')+', DBProcess/LadderCode '+ISNULL(@nvProcess,'')+'/'+ISNULL(@nvLadderCode,'');
							END
							ELSE IF ISNULL(@nvParam3,'') <> ''
								INSERT INTO @RPErrors(ErrorText)
								SELECT 'CDBPPX Insert Param2('+@nvParam2+'):'+ISNULL(@nvParam1,'')+', DBProcess/LadderCode '+ISNULL(@nvProcess,'')+'/'+ISNULL(@nvLadderCode,'');
						END
						ELSE IF ISNULL(@nvParam2,'') <> ''
							INSERT INTO @RPErrors(ErrorText)
							SELECT 'CDBPPX Insert Param1('+@nvParam1+'):, DBProcess/LadderCode '+ISNULL(@nvProcess,'')+'/'+ISNULL(@nvLadderCode,'');
					END
					UPDATE @RPBinaryTree
						SET Processed = 1
					WHERE NodeId = @iNodeId;
				END
				ELSE
					INSERT INTO @RPErrors(ErrorText)
					SELECT 'CDBPPX Insert Problem for DBProcess/LadderCode '+ISNULL(@nvProcess,'')+'/'+ISNULL(@nvLadderCode,'');
			END
			ELSE
			INSERT INTO @RPErrors(ErrorText)
			SELECT 'CDBPPX Already Exists DBProcess/LadderCode '+ISNULL(@nvProcess,'')+'/'+ISNULL(@nvLadderCode,'');
			--next record please
			FETCH csr_CompleteTree INTO @iNodeId,@iParentNodeId,@nvParentSuccess,@nvLadderCode,@nvProcess,@nvProcessSyn,@nvSuccess,@nvSuccessProcess,@nvContinueProcess,@nvDBProcessSuccessValue,
				@iLadderDBProcessXrefId,@iDBProcessSuccessLDBPXId,@iDBProcessContinueLDBPXId,@nvParam1,@nvParam2,@nvParam3,@nvParam4,@nvParam5,@nvExitLevel,@iProcessed;
		END
		CLOSE csr_CompleteTree;
		DEALLOCATE csr_CompleteTree;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		INSERT INTO @RPErrors(ErrorText)
		SELECT 'Associate each DBProcess with its external parameter values Problem ErrorDetailId='+CONVERT(NVARCHAR(10),@iErrorDetailId);
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
		COMMIT TRANSACTION;
	SELECT * FROM @RPErrors;
	SELECT * FROM @RPBinaryTree;
END
