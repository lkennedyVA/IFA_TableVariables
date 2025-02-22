USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgFieldDefinitionXrefInsertOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will insert a new record
	Tables: [organization].[OrgFieldDefinitionXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2016-07-18 - LBD - Modified, increased Format size
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgFieldDefinitionXrefInsertOut](
	 @piOrgId INT
	,@piFieldDefinitionId INT
	,@piStatusFlag INT 
	,@pnvFormat NVARCHAR(255) = NULL
	,@pbRequired BIT = NULL
	,@pbEncrypted BIT = NULL
	,@piMaxCount INT = NULL
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
		,@sSchemaName nvarchar(128) = N'organization';
	SET @iCurrentTransactionLevel = @@TRANCOUNT;
	BEGIN TRANSACTION
	BEGIN TRY
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
			,@piFieldDefinitionId
			,@pnvFormat
			,@pbRequired
			,@pbEncrypted
			,@piMaxCount
			,@piStatusFlag
			,SYSDATETIME()
			,@pnvUserName; 
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
		SELECT @piOrgFieldDefinitionXrefId = OrgFieldDefinitionXrefId
		FROM @OrgFieldDefinitionXref
	END
	END
