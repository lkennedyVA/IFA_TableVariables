USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspWLCustomerInsert
	Created By: Larry Dugger (pre CSharp)
	Descr: This procedure has no decent comments yet...

	Tables: [command].[Action]

	Functions: [command].[ufnKeyType] 
	
	Procedures: [command].[uspCommentInsertOut]
		,[command].[uspActionCommentXrefInsertOut]
		,[error].[uspLogErrorDetailInsertOut]
   
	History:
		2018-03-26 - CBS - Created
*****************************************************************************************/
ALTER PROCEDURE [command].[uspWLCustomerInsertOut](
	 @piOrgId INT 
	,@pbiKeyId BIGINT 
	,@psiActionTypeId SMALLINT
	,@piStatusFlag INT 
	,@pdtDateRetired DATETIME2(7)  
	,@pdtDateActivated DATETIME2(7)  
	,@pnvUserName NVARCHAR(100)
	,@pnvComment NVARCHAR(512) 
	,@pbiActionId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblAction TABLE ( 
		 ActionId bigint
	);
	DECLARE @biCommentId bigint
		,@biActionCommentXrefId bigint
		,@siKeyTypeId smallint = [command].[ufnKeyType]('Customer')
		,@iErrorDetailId int
		,@sSchemaName sysname = 'command';

	IF ISNULL(@psiActionTypeId, -1) = -1
		OR ISNULL(@siKeyTypeId, -1) = -1 
		OR ISNULL(@piOrgId, -1) = -1  
		OR ISNULL(@pbiKeyId, -1) = -1  
		OR ISNULL(@pdtDateRetired, '') = '' 
		OR ISNULL(@pdtDateActivated, '') = ''   
		OR ISNULL(@pnvUserName, '') = '' 
		OR ISNULL(@pnvComment, '') = '' 
	BEGIN
		RAISERROR ('Missing information needed to create Action record', 16, 1);
		RETURN
	END
	BEGIN TRY
		INSERT INTO [command].[Action](
			 ActionTypeId
			,OrgId
			,KeyId
			,KeyTypeId
			,StatusFlag
			,DateRetired
			,DateActivated
			,UserName
		)
		OUTPUT inserted.ActionId
		INTO @tblAction
		SELECT @psiActionTypeId
			,@piOrgId
			,@pbiKeyId
			,@siKeyTypeId
			,@piStatusFlag
			,@pdtDateRetired
			,@pdtDateActivated 
			,@pnvUserName;

		SELECT @pbiActionId = ActionId
		FROM @tblAction;
			
		IF ISNULL(@pbiActionId, -1) <> -1
			EXECUTE [command].[uspCommentInsertOut] @pnvComment=@pnvComment,@pnvUserName=@pnvUserName,@pbiCommentId=@biCommentId OUTPUT;
		IF ISNULL(@biCommentId, -1) <> -1
			EXECUTE [command].[uspActionCommentXrefInsertOut] @pbiActionId=@pbiActionId,@pbiCommentId=@biCommentId,@pbiActionCommentXrefId=@biActionCommentXrefId OUTPUT;
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName=@sSchemaName,@piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @pbiActionId = -1 * @iErrorDetailId;
		THROW;
	END CATCH;
END
