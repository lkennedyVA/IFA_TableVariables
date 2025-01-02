USE [IFA]
GO
/****** Object:  StoredProcedure [command].[uspActionFieldTypeXrefInsertOut]    Script Date: 1/2/2025 5:48:51 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspActionFieldTypeXrefInsertOut
	Created By: Chris Sharp
	Description: This procedure will insert an ActionFieldTypeXrefId 
		record

	Tables: [command].[ActionFieldTypeXref]

	Procedures: [error].[uspLogErrorDetailUpdateOut]
   
	History:
		2018-03-30 - CBS - Created
*****************************************************************************************/
ALTER PROCEDURE [command].[uspActionFieldTypeXrefInsertOut](
	 @pbiActionId BIGINT
	,@ptiFieldId TINYINT 
	,@pnvValue NVARCHAR(50)
	,@pbiActionFieldTypeXrefId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblActionFieldTypeXref TABLE (
		 ActionFieldTypeXrefId bigint
	);
	DECLARE @iErrorDetailId int
		,@sSchemaName sysname = N'command';

	BEGIN TRY
		IF NOT EXISTS (SELECT 'X'
					FROM [command].[ActionFieldTypeXref]
					WHERE ActionId = @pbiActionId
						AND FieldTypeId = @ptiFieldId)
		BEGIN
			INSERT INTO [command].[ActionFieldTypeXref] (
				 ActionId
				,FieldTypeId
				,[Value]
				,StatusFlag
				,DateActivated
			)
			OUTPUT inserted.ActionFieldTypeXrefId
			INTO @tblActionFieldTypeXref
			SELECT @pbiActionId
				,@ptiFieldId
				,@pnvValue
				,1 AS StatusFlag
				,SYSDATETIME() AS DateActivated;
			
			SELECT @pbiActionFieldTypeXrefId = ActionFieldTypeXrefId 
			FROM @tblActionFieldTypeXref;
		END
		ELSE 
		BEGIN
			RAISERROR ('ActionFieldXrefId already exists for ActionId and FieldTypeId', 16, 1);
			RETURN
		END	
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @pbiActionFieldTypeXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		THROW
	END CATCH
END
