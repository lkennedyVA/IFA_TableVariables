USE [IFA]
GO
/****** Object:  StoredProcedure [command].[uspWLPayerInsertOut]    Script Date: 1/2/2025 6:09:15 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspWLPayerInsert
	Created By: Chris Sharp
	Descr: This procedure will insert a new, Active White List Payer record 
		and requires each of the listed parameters.  Based on conversations 
		between Hal and Larry, for consistency, we return the same fields post
		insert as we do in [command].[uspActionDeactivate]. (ActionID, StatusFlag 
		and DateActivated)  

		After the Action record is inserted, we insert a record into [command].[ActionFieldTypeXref] 
		via [command].[uspActionFieldTypeXrefInsertOut]

		Next, we insert a comment into [command].[Comment] via [command].[uspCommentInsertOut].

		Finally, we insert an Xref record associating the ActionID and CommentID into 
		[command].[ActionCommentXref] via [command].[uspActionCommentXrefInsertOut]

	Tables: [command].[Action]

	Functions: [command].[ufnKeyType] 
		,[command].[ufnFieldType]

	Procedures: [command].[uspActionFieldTypeXrefInsertOut]
		,[command].[uspCommentInsertOut]
		,[command].[uspActionCommentXrefInsertOut] 
   
	History:
		2018-03-30 - CBS - Created
*****************************************************************************************/
ALTER PROCEDURE [command].[uspWLPayerInsertOut](
	 @piOrgId INT 
	,@pbiPayerId BIGINT 
	,@psiActionTypeId SMALLINT
	,@pmItemAmountCeiling MONEY
	,@pdtDateRetired DATETIME2(7)  
	,@pnvUserName NVARCHAR(100)
	,@pnvComment NVARCHAR(512) 
	,@pbiActionId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblWLPayerInsertOut TABLE ( 
		 ActionId bigint not null
		,StatusFlag int not null
		,DateActivated datetime2(7) not null
	);
	DECLARE @biCommentId bigint
		,@biActionCommentXrefId bigint
		,@biActionFieldTypeXrefId bigint
		,@tiItemAmountCeilingFieldId tinyint = [command].[ufnFieldType]('ItemAmountCeiling')
		,@siKeyTypeId smallint = [command].[ufnKeyType]('Payer')
		,@nvValue nvarchar(50) = ISNULL(TRY_CONVERT(nvarchar(50),@pmItemAmountCeiling), '0.00')
		,@iErrorDetailId int
		,@sSchemaName sysname = 'command';

	IF ISNULL(@psiActionTypeId, -1) = -1
		OR ISNULL(@siKeyTypeId, -1) = -1 	
		OR ISNULL(@piOrgId, -1) = -1  
		OR ISNULL(@pmItemAmountCeiling, -1.00) = -1.00
		OR ISNULL(@pbiPayerId, -1) = -1  
		OR ISNULL(@pdtDateRetired, '') = '' 
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
			,inserted.StatusFlag
			,inserted.DateActivated
		INTO @tblWLPayerInsertOut
		SELECT @psiActionTypeId
			,@piOrgId
			,@pbiPayerId
			,@siKeyTypeId
			,1 AS StatusFlag
			,@pdtDateRetired
			,SYSDATETIME() AS DateActivated 
			,@pnvUserName;

		SELECT @pbiActionId = ActionId
		FROM @tblWLPayerInsertOut;
			
		IF ISNULL(@pbiActionId, -1) <> -1  
			AND ISNULL(@tiItemAmountCeilingFieldId, -1) <> -1
			EXECUTE [command].[uspActionFieldTypeXrefInsertOut] @pbiActionId=@pbiActionId, @ptiFieldId=@tiItemAmountCeilingFieldId, @pnvValue=@nvValue, @pbiActionFieldTypeXrefId=@biActionFieldTypeXrefId OUTPUT;
		IF ISNULL(@pbiActionId, -1) <> -1
			EXECUTE [command].[uspCommentInsertOut] @pnvComment=@pnvComment,@pnvUserName=@pnvUserName,@pbiCommentId=@biCommentId OUTPUT;
		IF ISNULL(@biCommentId, -1) <> -1
			EXECUTE [command].[uspActionCommentXrefInsertOut] @pbiActionId=@pbiActionId,@pbiCommentId=@biCommentId,@pbiActionCommentXrefId=@biActionCommentXrefId OUTPUT;

		SELECT ActionId
			,StatusFlag
			,DateActivated
		FROM @tblWLPayerInsertOut;

	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName=@sSchemaName,@piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @pbiActionId = -1 * @iErrorDetailId;
		THROW;
	END CATCH;
END
