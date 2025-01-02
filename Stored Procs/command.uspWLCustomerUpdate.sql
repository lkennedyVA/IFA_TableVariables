USE [IFA]
GO
/****** Object:  StoredProcedure [command].[uspWLCustomerUpdate]    Script Date: 1/2/2025 6:08:47 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspWLCustomerUpdate
	Created By: Larry Dugger per CSharp
	Descr: This procedure has no decent comments yet...

	Tables: [command].[Action]

	Procedures: [command].[uspCommentInsertOut]
		,[command].[uspActionCommentXrefInsertOut]
		,[error].[uspLogErrorDetailInsertOut]
   
	History:
		2018-03-26 - CBS - Created
*****************************************************************************************/
ALTER PROCEDURE [command].[uspWLCustomerUpdate](
	 @pbiActionId BIGINT
	,@piStatusFlag INT 
	,@pdtDateRetired DATETIME2(7)  
	,@pdtDateActivated DATETIME2(7)  
	,@pnvUserName NVARCHAR(100)
	,@pnvComment NVARCHAR(512) 
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblAction TABLE ( 
		 ActionId bigint not null
	);
	DECLARE @biActionId bigint
		,@biCommentId bigint
		,@biActionCommentXrefId bigint
		,@iErrorDetailId int
		,@sSchemaName sysname = 'command';

	IF ISNULL(@pdtDateRetired, '') = '' 
		OR ISNULL(@pbiActionId, -1) = -1
		OR ISNULL(@piStatusFlag, -1) = -1
		OR ISNULL(@pdtDateActivated, '') = ''   
		OR ISNULL(@pnvUserName, '') = '' 
		OR ISNULL(@pnvComment, '') = '' 
	BEGIN
		RAISERROR ('Missing information needed to update Action record', 16, 1);
		RETURN
	END
	BEGIN TRY
		UPDATE [command].[Action]
		SET DateRetired = @pdtDateRetired
			,DateActivated = @pdtDateActivated
			,StatusFlag = @piStatusFlag
			,UserName = @pnvUserName
		WHERE ActionId = @pbiActionId;

		EXECUTE [command].[uspCommentInsertOut] @pnvComment=@pnvComment,@pnvUserName=@pnvUserName,@pbiCommentId=@biCommentId OUTPUT;
		IF ISNULL(@biCommentId, -1) <> -1
			EXECUTE [command].[uspActionCommentXrefInsertOut] @pbiActionId=@pbiActionId,@pbiCommentId=@biCommentId,@pbiActionCommentXrefId=@biActionCommentXrefId OUTPUT;
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName=@sSchemaName,@piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @pbiActionId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		THROW;
	END CATCH;
END
