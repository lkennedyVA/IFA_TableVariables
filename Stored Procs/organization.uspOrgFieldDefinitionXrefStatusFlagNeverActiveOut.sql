USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspOrgFieldDefinitionXrefStatusFlagNeverActiveOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Descr: This procedure will Activate the OrgFieldDefinitionXref (StatusFlag=3)
	Tables: [organization].[OrgFieldDefinitionXref]
   
	Functions: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
		2016-07-18 - LBD - Modified, increased Format size
		2017-06-03 - LBD - Modified, removed use of archive tables
*****************************************************************************************/
ALTER PROCEDURE [organization].[uspOrgFieldDefinitionXrefStatusFlagNeverActiveOut](
	 @pnvUserName NVARCHAR(100) = 'N/A'
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
	BEGIN
		BEGIN TRANSACTION
		BEGIN TRY
			UPDATE [organization].[OrgFieldDefinitionXref]
			SET StatusFlag = 3
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
			----Anytime an update occurs we place an original copy in an archive table
			--INSERT INTO [archive].[OrgFieldDefinitionXref](OrgFieldDefinitionXrefId
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
			--,SYSDATETIME()
			--FROM @OrgFieldDefinitionXref
		END TRY
		BEGIN CATCH
			IF @@TRANCOUNT > @iCurrentTransactionLevel
			ROLLBACK TRANSACTION;
			EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
			SET @piOrgFieldDefinitionXrefId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
		END CATCH;
		IF @@TRANCOUNT > @iCurrentTransactionLevel
		BEGIN
			COMMIT TRANSACTION;
			SELECT @piOrgFieldDefinitionXrefId = OrgFieldDefinitionXrefId
			FROM @OrgFieldDefinitionXref;
		END
	END
END
