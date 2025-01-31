USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgFieldDefinitionXrefUpsertOut
	CreatedBy: Larry Dugger
	Date: 2014-11-05
	Descr: This procedure will insert a new record
	Tables: [organization].[OrgFieldDefinitionXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2014-11-05 - LBD - Created
		2016-07-18 - LBD - Modified, increased Format size
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgFieldDefinitionXrefUpsertOut](
	 @piOrgId INT
	,@pnvStructureReference NVARCHAR(255)
	,@pnvFormat NVARCHAR(255)
	,@pbRequired BIT
	,@pbEncrypted BIT
	,@piMaxCount INT
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgFieldDefinitionXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgFieldDefinitionXref table (
		 OrgFieldDefinitionXrefId int
		,OrgId int
		,FieldDefinitionId int
		,[Format] nvarchar(255)
		,[Required] bit
		,[Encrypted] bit
		,MaxCount int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName SYSNAME
		,@iFieldDefinitionId INT = 0
		,@nvMessage nvarchar(256) = '';
	SET @sSchemaName = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	SET @piOrgFieldDefinitionXrefId = 0;
	SELECT @iFieldDefinitionId = FieldDefinitionId
	FROM [common].[FieldDefinition]
	WHERE StructureReference = @pnvStructureReference;
	
	IF @iFieldDefinitionId > 0
	BEGIN
		SELECT @piOrgFieldDefinitionXrefId = OrgFieldDefinitionXrefId
		FROM [organization].[OrgFieldDefinitionXref]
		WHERE OrgId = @piOrgId
			AND FieldDefinitionId = @iFieldDefinitionId;
		IF @piOrgFieldDefinitionXrefId > 0
		BEGIN
			BEGIN TRY
			BEGIN TRANSACTION
			--SET NOCOUNT ON
			----Anytime an update occurs we place a copy in an archive table
			--INSERT INTO [archive].[OrgFieldDefinitionXref](
			--		OrgFieldDefinitionXrefId
			--	,OrgId
			--	,FieldDefinitionId            
			--	,[Format]
			--	,[Required]
			--	,[Encrypted]	
			--	,MaxCount		
			--	,StatusFlag
			--	,DateActivated
			--	,UserName
			--	,DateArchived
			--) 
			--SELECT OrgFieldDefinitionXrefId
			--	,OrgId
			--	,FieldDefinitionId
			--	,[Format]
			--	,[Required]
			--	,[Encrypted]	
			--	,MaxCount		
			--	,StatusFlag
			--	,DateActivated
			--	,UserName
			--	,SYSDATETIME()
			--FROM @OrgFieldDefinitionXref;
			SET NOCOUNT ON
			UPDATE [organization].[OrgFieldDefinitionXref]
				SET [Format] = @pnvFormat
					,[Required] = @pbRequired
					,[Encrypted] = @pbEncrypted
					,MaxCount = @piMaxCount
					,StatusFlag = @piStatusFlag
					,DateActivated = SYSDATETIME()    
					,UserName = @pnvUserName     
				OUTPUT deleted.OrgFieldDefinitionXrefId
					,deleted.OrgId
					,deleted.FieldDefinitionId
					,deleted.[Format]
					,deleted.[Required]
					,deleted.[Encrypted]
					,deleted.MaxCount
					,deleted.StatusFlag
					,deleted.DateActivated
					,deleted.UserName
			INTO @OrgFieldDefinitionXref
			WHERE OrgFieldDefinitionXrefId = @piOrgFieldDefinitionXrefId;
			SET NOCOUNT OFF
			END TRY
			BEGIN CATCH
				IF @@TRANCOUNT > @iCurrentTransactionLevel
					ROLLBACK TRANSACTION;
				EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
				THROW;
			END CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				COMMIT TRANSACTION;
				SELECT @piOrgFieldDefinitionXrefId = OrgFieldDefinitionXrefId
				FROM @OrgFieldDefinitionXref;
		END
		ELSE
		BEGIN
			BEGIN TRY
			BEGIN TRANSACTION
			SET NOCOUNT ON
			INSERT INTO [organization].[OrgFieldDefinitionXref]
				OUTPUT inserted.OrgFieldDefinitionXrefId
					,inserted.OrgId
					,inserted.FieldDefinitionId
					,inserted.[Format]
					,inserted.[Required]
					,inserted.[Encrypted]
					,inserted.MaxCount
					,inserted.StatusFlag
					,inserted.DateActivated
					,inserted.UserName
				INTO @OrgFieldDefinitionXref
			SELECT @piOrgId
				,@iFieldDefinitionId
				,@pnvFormat
				,@pbRequired
				,@pbEncrypted
				,@piMaxCount
				,@piStatusFlag
				,SYSDATETIME()
				,@pnvUserName;
			SET NOCOUNT OFF	 
			END TRY
			BEGIN CATCH
				IF @@TRANCOUNT > @iCurrentTransactionLevel
					ROLLBACK TRANSACTION;
				EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
				THROW;
			END CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
				COMMIT TRANSACTION;
				SELECT @piOrgFieldDefinitionXrefId = OrgFieldDefinitionXrefId
				FROM @OrgFieldDefinitionXref;
		END
	END
	ELSE
	BEGIN
		SET @nvMessage = @pnvStructureReference+' @pnvStructureReference doesnot exist in [common].[FieldDefinition].';
		RAISERROR (@nvMessage, 16, 1);
	END
END
