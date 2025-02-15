USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspRCLadderTemplateImport
	CreatedBy: Larry Dugger
	Date: 2015-11-11
	Descr: This procedure populates the risk processing structure
		It accesses an Excel template which has been pre-imported
		It currently depends on the following tables and relationships being
		pre-populated:
			[riskprocessing].[RC]
			,[riskprocessing].[RP]
		Once executed it will populate the following tables:
			[riskprocessing].[RCLadderTop]
			,[riskprocessing].[LadderTopXref]
	Tables: [dbo].[BulkRCLadder]
		[riskprocessing].[RC]
		,[riskprocessing].[RP]
      
	Procedures: 
      
	Functions: 
	History:
		2015-11-11 - LBD - Created using new template structure
		2018-04-05 - LBD - Modified, adjsut insert of RCLadderTop, so 
			StatusFlag = 2, which allows for a quicker transition when online. 
*****************************************************************************************/
ALTER PROCEDURE [riskprocessing].[uspRCLadderTemplateImport]
AS
BEGIN
	SET NOCOUNT ON
	DECLARE @RCErrors table(
		Id int identity(1,1)
		,ErrorText nvarchar(255)
	);
	DECLARE @RCBinaryTree table(
		NodeId int identity(1,1)
		,ParentNodeId int
		,ParentSuccess nvarchar(3)
		,BulkRCLadderIdYes int
		,BulkRCLadderIdNo int
		,RCName nvarchar(50)
		,RPName nvarchar(50)
		,OrgName nvarchar(50)
		,OrgType nvarchar(50)
		,CollectionName nvarchar(100)
		,LadderName nvarchar(50)
		,LadderNameSyn nvarchar(50)
		,Success nvarchar(3)
		,SuccessLadder nvarchar(50)
		,SuccessLadderSyn nvarchar(50)
		,ContinueLadder nvarchar(50)
		,ContinueLadderSyn nvarchar(50)
		,Processed int
		,LadderTopXrefId int
		,LadderSuccessValue nvarchar(512)
		,LadderSuccessLTXId int
		,LadderContinueLTXId int
		);
	DECLARE @nvUserName nvarchar(100) = 'System'
		,@iStatusFlag int = 1
		,@iRCLadderTopStatusFlag int = 2
		,@iBulkRCLadderId int
		,@iParentNodeId int
		,@nvRCName nvarchar(50)
		,@nvRPName nvarchar(50)
		,@nvOrgName nvarchar(50)
		,@nvOrgType nvarchar(50)
		,@nvCollectionName nvarchar(100)
		,@nvLadderName nvarchar(100)
		,@nvLadderNameSyn nvarchar(50)
		,@nvSuccess nvarchar(3)
		,@nvSuccessLadder nvarchar(50)
		,@nvSuccessLadderSyn nvarchar(50)
		,@nvContinueLadder nvarchar(50)
		,@nvContinueLadderSyn nvarchar(50)
		,@iNodeId int
		,@nvParentSuccess nvarchar(3)
		,@iCnt int = 0
		,@iProcessed int = -1
		,@iLadderTopId int
		,@iRCLadderTopId int
		,@iLadderSuccessLTXId int
		,@iLadderContinueLTXId int
		,@nvSuccessValue nvarchar(512)
		,@iLadderTopXrefId int
		,@nvTitle nvarchar(255)
		,@iRCId int
		,@iRPId int
		,@iOrgId int
		,@iOrgXrefId int
		,@iErrorDetailId int
		,@iCurrentTransactionLevel int
		,@sSchemaName sysname;
	SET @sSchemaName = N'riskprocessing';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	--Translate Template  
	BEGIN TRANSACTION
	BEGIN TRY
		DECLARE csr_Translate CURSOR FOR
		SELECT BulkRCLadderId
			,RCName
			,RPName
			,OrgName
			,OrgType
			,RiskCollectionName
			,LadderCollectionName
			,CASE WHEN charindex('#',LadderCollectionName) = 0 THEN NULL ELSE SubString(LadderCollectionName,1,CASE WHEN charindex('#',LadderCollectionName) = 0 THEN LadderCollectionName ELSE charindex('#',LadderCollectionName)-1 END)  END 
			,Success
			,SuccessLadder
			,CASE WHEN charindex('#',SuccessLadder) = 0 THEN NULL ELSE SubString(SuccessLadder,1,CASE WHEN charindex('#',SuccessLadder) = 0 THEN SuccessLadder ELSE charindex('#',SuccessLadder)-1 END)  END
			,ContinueLadder
			,CASE WHEN charindex('#',ContinueLadder) = 0 THEN NULL ELSE SubString(ContinueLadder,1,CASE WHEN charindex('#',ContinueLadder) = 0 THEN ContinueLadder ELSE charindex('#',ContinueLadder)-1 END)  END
		FROM [dbo].[BulkRCLadder] b
		WHERE Processed = 0
		ORDER BY BulkRCLadderId;
		OPEN csr_Translate;
		FETCH csr_Translate INTO @iBulkRCLadderId,@nvRCName,@nvRPName,@nvOrgName,@nvOrgType,@nvCollectionName,
			@nvLadderName,@nvLadderNameSyn,@nvSuccess,@nvSuccessLadder,@nvSuccessLadderSyn,@nvContinueLadder,@nvContinueLadderSyn;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			--NEW LadderCollection set node id to 0, establish RCLadderTop
			IF NOT EXISTS (SELECT 'X' FROM @RCBinaryTree 
						WHERE RCName = @nvRCName
									AND OrgName = @nvOrgName
									AND OrgType = @nvOrgType
									AND CollectionName = @nvCollectionName)
			SET @iNodeId = 0;
			--Ladder chain associated with node 0 RCLAdderTop.LadderTopXrefId
			IF NOT EXISTS (SELECT 'X' FROM @RCBinaryTree 
						WHERE RCName = @nvRCName
									AND OrgName = @nvOrgName
									AND OrgType = @nvOrgType
									AND CollectionName = @nvCollectionName
									AND LadderName = @nvLadderName)
			BEGIN 
			--DOES Parent exists, if so set what success value causes this path to be executed?
			SELECT @iNodeId = NodeId
				,@nvParentSuccess=CASE WHEN SuccessLadder = @nvLadderName THEN
											CASE WHEN Success = 'Yes' THEN 'Yes' ELSE 'No' END 
										WHEN ContinueLadder = @nvLadderName THEN
											CASE WHEN Success = 'Yes' THEN 'No' ELSE 'Yes' END 
									END
			FROM @RCBinaryTree
			WHERE RCName = @nvRCName
					AND OrgName = @nvOrgName
					AND OrgType = @nvOrgType
					AND CollectionName = @nvCollectionName
				AND (SuccessLadder = @nvLadderName 
						OR ContinueLadder = @nvLadderName);
				--INSERT this node
			INSERT INTO @RCBinaryTree(ParentNodeId,ParentSuccess,BulkRCLadderIdYes,RCName,RPName,OrgName,OrgType,CollectionName,
					LadderName,LadderNameSyn,Success,SuccessLadder,SuccessLadderSyn,ContinueLadder,ContinueLadderSyn,Processed)
			SELECT @iNodeId,@nvParentSuccess,@iBulkRCLadderId,@nvRCName,@nvRPName,@nvOrgName,@nvOrgType,@nvCollectionName,
					@nvLadderName,@nvLadderNameSyn,@nvSuccess,@nvSuccessLadder,@nvSuccessLadderSyn,@nvContinueLadder,@nvContinueLadderSyn,@iProcessed;
			SET @iNodeId = SCOPE_IDENTITY();
			IF @nvParentSuccess IS NULL 
				SET @nvParentSuccess = @nvSuccess;
			END
			UPDATE [dbo].[BulkRCLadder] set Processed = 1 WHERE BulkRCLadderId = @iBulkRCLadderId;
			FETCH csr_Translate INTO @iBulkRCLadderId,@nvRCName,@nvRPName,@nvOrgName,@nvOrgType,@nvCollectionName,
				@nvLadderName,@nvLadderNameSyn,@nvSuccess,@nvSuccessLadder,@nvSuccessLadderSyn,@nvContinueLadder,@nvContinueLadderSyn;
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
		INSERT INTO @RCErrors(ErrorText)
		SELECT 'Translate Template Problem ErrorDetailId='+CONVERT(NVARCHAR(10),@iErrorDetailId);
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
		COMMIT TRANSACTION;
	--HERE IS WHERE WE MIGRATE the Binary Tree to the system
	--DEBUG select * from @RCBinaryTree
	--RCLadderTop
	--LadderTopXref Creation
	BEGIN TRANSACTION
	BEGIN TRY
		DECLARE csr_BuildTree CURSOR FOR
		SELECT NodeId,ParentNodeId,ParentSuccess,RCName,RPName,OrgName,OrgType,CollectionName,
			LadderName,LadderNameSyn,Success,SuccessLadder,SuccessLadderSyn,ContinueLadder,ContinueLadderSyn,Processed
		FROM @RCBinaryTree
		ORDER BY NodeId;
		OPEN csr_BuildTree;
		FETCH csr_BuildTree INTO @iNodeId,@iParentNodeId,@nvParentSuccess,@nvRCName,@nvRPName,@nvOrgName,@nvOrgType,@nvCollectionName,
			@nvLadderName,@nvLadderNameSyn,@nvSuccess,@nvSuccessLadder,@nvSuccessLadderSyn,@nvContinueLadder,@nvContinueLadderSyn,@iProcessed;
		WHILE @@FETCH_STATUS = 0
		BEGIN 
			SET @iLadderTopId = 0;
			SET @iLadderSuccessLTXId = 0;
			SET @iLadderContinueLTXId = 0;
			SET @iLadderTopXrefId = 0;
			SET @iRPId = -1;
			SET @iOrgXrefId = -1;
			--GET LadderTop based on the CollectionName or it's equivalent Synonym
			IF ISNULL(@nvLadderNameSyn,'') = ''
				EXECUTE [riskprocessing].[uspLadderTopSelectOut] @piRPId=@iRPId, /*@piOrgXrefId=@iOrgXrefId,*/
					@pnvCollectionName=@nvLadderName, @piLadderTopId=@iLadderTopId OUTPUT;
			ELSE
				EXECUTE [riskprocessing].[uspLadderTopSelectOut] @piRPId=@iRPId, /*@piOrgXrefId=@iOrgXrefId,*/
					@pnvCollectionName=@nvLadderNameSyn, @piLadderTopId=@iLadderTopId OUTPUT;
			IF @iLadderTopId <> 0
			BEGIN
			SET @nvSuccessValue = CASE WHEN @nvSuccess = 'Yes' THEN 1 WHEN @nvSuccess= 'No' THEN 0 ELSE NULL END
				IF ISNULL(@nvLadderNameSyn,'') = ''
					SET @nvTitle = 'Process Ladder '+@nvLadderName +' for '+@nvCollectionName
				ELSE
					SET @nvTitle = 'Process Ladder '+@nvLadderNameSyn +' for '+@nvCollectionName 
			--FIRST we insert each record   
			IF @iLadderTopXrefId = 0
				EXECUTE [riskprocessing].[uspLadderTopXrefInsertOut]
							@pnvTitle = @nvTitle
					,@piLadderTopId = @iLadderTopId
					,@pnvLadderSuccessValue = @nvSuccessValue
					,@piLadderSuccessLTXId = 0
					,@piLadderContinueLTXId = 0
					,@piStatusFlag = @iStatusFlag
					,@pnvUserName = @nvUserName
					,@piLadderTopXrefId = @iLadderTopXrefId OUTPUT;
			IF @iLadderTopXrefId > 0
				BEGIN
				UPDATE @RCBinaryTree
					SET LadderTopXrefId =  @iLadderTopXrefId
						,LadderSuccessValue = @nvSuccessValue
						,Processed = 0
				WHERE NodeId = @iNodeId;
					--IS this the Start of a path? If so create an RCLadderTop entry.
					IF @iParentNodeId = 0
					BEGIN 
						SELECT @iRCId = RCId
						FROM [riskprocessing].[RC]
						WHERE Name = @nvRCName;
						SET @iOrgXrefId = [common].[ufnDimensionOrgNameToOrgXref]('RiskControl',@nvOrgName,@nvOrgType);
						SET @iLadderTopId = 0;
						EXECUTE [riskprocessing].[uspRCLadderTopInsertOut]
								@piRCId = @iRCId
							,@piOrgXrefId = @iOrgXrefId
							,@piLadderTopXrefId = @iLadderTopXrefId
							,@pnvCollectionName = @nvCollectionName
							,@piStatusFlag = @iRCLadderTopStatusFlag --2018-04-05
							,@pnvUserName = @nvUserName
							,@piRCLadderTopId = @iRCLadderTopId OUTPUT;
						IF @iRCLadderTopId < 1
							INSERT INTO @RCErrors(ErrorText)
							SELECT 'Error inserting RCLadderTop for RC/Org of type '+ISNULL(@nvRCName,'')+'/'+ISNULL(@nvOrgName,'')+'/'+ISNULL(@nvOrgType,'');
					END
				END
			ELSE
				INSERT INTO @RCErrors(ErrorText)
				SELECT 'Error inserting LadderTopXref '+ISNULL(@iLadderTopId,'');
			END
			FETCH csr_BuildTree INTO @iNodeId,@iParentNodeId,@nvParentSuccess,@nvRCName,@nvRPName,@nvOrgName,@nvOrgType,@nvCollectionName,
				@nvLadderName,@nvLadderNameSyn,@nvSuccess,@nvSuccessLadder,@nvSuccessLadderSyn,@nvContinueLadder,@nvContinueLadderSyn,@iProcessed;
		END
		CLOSE csr_BuildTree;
		DEALLOCATE csr_BuildTree;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		INSERT INTO @RCErrors(ErrorText)
		SELECT 'LadderTopXref/RCLadderTop Creation Problem ErrorDetailId='+CONVERT(NVARCHAR(10),@iErrorDetailId);
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
		COMMIT TRANSACTION;
	--DEBUG select * from @RCBinaryTree
	--SET LadderTopXrefId Success and Continue, being cognizant of the Success path i.e. ParentSuccess
	BEGIN TRANSACTION
	BEGIN TRY
		--LOAD the xref info just established into the proper slots
		UPDATE bt
			SET LadderSuccessLTXId = bts.LadderSuccessLTXId
		FROM @RCBinaryTree bt
		INNER JOIN @RCBinaryTree bts ON bt.NodeId = bts.ParentNodeId
									AND bts.ParentSuccess = 'Yes'
		WHERE bt.Success = 'Yes';
		UPDATE bt
			SET LadderContinueLTXId = btc.LadderContinueLTXId
		FROM @RCBinaryTree bt
		INNER JOIN @RCBinaryTree btc ON bt.NodeId = btc.ParentNodeId
									AND btc.ParentSuccess = 'No'
		WHERE bt.Success = 'Yes';
		UPDATE bt
			SET LadderContinueLTXId = bts.LadderSuccessLTXId
		FROM @RCBinaryTree bt
		INNER JOIN @RCBinaryTree bts ON bt.NodeId = bts.ParentNodeId
									AND bts.ParentSuccess = 'Yes'
		WHERE bt.Success = 'No';
		UPDATE bt
			SET LadderSuccessLTXId = btc.LadderContinueLTXId
		FROM @RCBinaryTree bt
		INNER JOIN @RCBinaryTree btc ON bt.NodeId = btc.ParentNodeId
									AND btc.ParentSuccess = 'No'
		WHERE bt.Success = 'No';
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		INSERT INTO @RCErrors(ErrorText)
		SELECT 'Set LadderTopXref Success and Continue Problem ErrorDetailId='+CONVERT(NVARCHAR(10),@iErrorDetailId);
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
		COMMIT TRANSACTION;
	
	--DEBUG select * from @RCBinaryTree
	--THIS allows us to associate multiple nodes with the same parent node
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE r
			SET LadderSuccessLTXId = r2.LadderTopXrefId
		FROM @RCBinaryTree r
		INNER JOIN @RCBinaryTree r2 ON r.CollectionName = r2.CollectionName
												AND CASE WHEN ISNULL(r.SuccessLadderSyn,'') = '' THEN r.SuccessLadder ELSE r.SuccessLadderSyn END
												= CASE WHEN ISNULL(r2.LadderNameSyn,'') = '' THEN r2.LadderName ELSE r2.LadderNameSyn END												
		WHERE r.LadderSuccessLTXId IS NULL;
		UPDATE r
			SET LadderContinueLTXId = r2.LadderTopXrefId
		FROM @RCBinaryTree r
		INNER JOIN @RCBinaryTree r2 ON r.CollectionName = r2.CollectionName
											AND CASE WHEN ISNULL(r.ContinueLadderSyn,'') = '' THEN r.ContinueLadder ELSE r.ContinueLadderSyn END
												= CASE WHEN ISNULL(r2.LadderNameSyn,'') = '' THEN r2.LadderName ELSE r2.LadderNameSyn END
		WHERE r.LadderContinueLTXId IS NULL;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		INSERT INTO @RCErrors(ErrorText)
		SELECT 'Set LadderTopXref Success and Continue Problem ErrorDetailId='+CONVERT(NVARCHAR(10),@iErrorDetailId);
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
		COMMIT TRANSACTION;
	
	--DEBUG select * from @RCBinaryTree
	--NOW Update the real binary tree table
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE ltx
		SET LadderSuccessLTXId = ISNULL(bt.LadderSuccessLTXId,0)
			,LadderContinueLTXId = ISNULL(bt.LadderContinueLTXId,0)
		FROM [riskprocessing].[LadderTopXref] ltx
		INNER JOIN @RCBinaryTree bt ON ltx.LadderTopXrefid = bt.LadderTopXrefId;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		INSERT INTO @RCErrors(ErrorText)
		SELECT 'Set LadderTopXref Update Problem ErrorDetailId='+CONVERT(NVARCHAR(10),@iErrorDetailId);
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
		COMMIT TRANSACTION;
   
	SELECT * FROM @RCErrors;
	SELECT * FROM @RCBinaryTree;
	IF EXISTS (SELECT 'X' FROM @RCErrors) 
		RETURN -1
	ELSE 
		RETURN 0
END
