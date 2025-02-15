USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgFieldDefinitionXrefUpdateOut
	CreatedBy: Larry Dugger
	Date: 2015-05-26
	Descr: This procedure will update the OrgFieldDefinitionXref
	Tables: [organization].[OrgFieldDefinitionXref]
   
	Functions: [common].[uspLogErrorDetailInsertOut]
	History:
		2015-05-26 - LBD - Created
		2016-07-18 - LBD - Modified, increased Format size
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgFieldDefinitionXrefUpdateOut](
	 @pnvFormat NVARCHAR(255) = NULL
	,@pbRequired BIT = NULL
	,@pbEncrypted BIT = NULL
	,@piMaxCount INT = NULL
	,@piStatusFlag INT = NULL
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piOrgFieldDefinitionXrefId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @OrgFieldDefinitionXref table (
		 OrgFieldDefinitionXrefId int not null
		,OrgId int not null
		,FieldDefinitionId int not null
		,[Format] nvarchar(255) null
		,[Required] bit not null
		,[Encrypted] bit not null
		,MaxCount int null
		,StatusFlag int not null
		,DateActivated datetime2(7) not null
		,UserName nvarchar(100) not null
	);
	DECLARE @iErrorDetailId INT
		,@iCurrentTransactionLevel INT
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
		UPDATE [organization].[OrgFieldDefinitionXref]
		SET [Format] = CASE WHEN ISNULL(@pnvFormat,'') <> '' THEN @pnvFormat ELSE [Format] END
			,[Required] = CASE WHEN ISNULL(@pbRequired,'') <> '' THEN @pbRequired ELSE [Required] END
			,[Encrypted] = CASE WHEN ISNULL(@pbEncrypted,'') <> '' THEN @pbEncrypted ELSE [Encrypted] END
			,MaxCount = CASE WHEN ISNULL(@piMaxCount,'') <> '' THEN @piMaxCount ELSE MaxCount END
			,StatusFlag = CASE WHEN ISNULL(@piStatusFlag,'') <> '' THEN @piStatusFlag ELSE StatusFlag END
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
		--FROM @OrgFieldDefinitionXref
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piOrgFieldDefinitionXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		THROW
	END CATCH;
	IF @@TRANCOUNT > @iCurrentTransactionLevel
	BEGIN
		COMMIT TRANSACTION;
		RETURN 1;
	END
END
