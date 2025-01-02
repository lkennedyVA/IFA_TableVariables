USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspActionTypeFieldTypeXrefInsertOut
	Created By: Chris Sharp
	Description: This procedure will insert a new ActionTypeFieldTypeXref record

	Tables: [command].[ActionTypeFieldTypeXref]

	Functions: [command].[ufnActionType]
		,[command].[ufnFieldType]

	Procedures: [error].[uspLogErrorDetailUpdateOut]
   
	History:
		2018-03-30 - CBS - Created
		2018-06-26 - CBS - Modified, corrected @pnvFieldTypeName from 
			TINYINT to NVARCHAR(100)
*****************************************************************************************/
ALTER PROCEDURE [command].[uspActionTypeFieldTypeXrefInsertOut](
	 @pnvActionTypeCode NVARCHAR(25)
	,@pnvFieldTypeName NVARCHAR(100) --2018-06-26
	,@pnvActionTypeFieldName NVARCHAR(100)
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100)
	,@pbiActionTypeFieldTypeXrefId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblActionTypeFieldTypeXref TABLE (
		 ActionTypeFieldTypeXrefId bigint
	);
	DECLARE @iErrorDetailId int
		,@siActionTypeId smallint = [command].[ufnActionType](@pnvActionTypeCode)
		,@tiFieldTypeId tinyint = [command].[ufnFieldType](@pnvFieldTypeName)
		,@nvActionTypeFieldName nvarchar(100)
		,@sSchemaName sysname = N'command';

	SET @nvActionTypeFieldName = ISNULL(TRY_CONVERT(nvarchar(100), @pnvActionTypeCode+ '_' +@pnvFieldTypeName), N'Somethings jacked inside '+OBJECT_NAME(@@PROCID));

	BEGIN TRY
		IF NOT EXISTS (SELECT 'X'
					FROM [command].[ActionTypeFieldTypeXref] 
					WHERE ActionTypeId = @siActionTypeId
						AND FieldTypeId = @tiFieldTypeId)
		BEGIN
			INSERT INTO [command].[ActionTypeFieldTypeXref] (
				 ActionTypeId
				,FieldTypeId
				,ActionTypeFieldName
				,StatusFlag
				,DateActivated
				,UserName
			)
			OUTPUT inserted.ActionTypeFieldTypeXrefId
			INTO @tblActionTypeFieldTypeXref
			SELECT @siActionTypeId
				,@tiFieldTypeId 
				,@nvActionTypeFieldName
				,@piStatusFlag
				,SYSDATETIME() AS DateActivated
				,@pnvUserName;

			SELECT @pbiActionTypeFieldTypeXrefId = ActionTypeFieldTypeXrefId 
			FROM @tblActionTypeFieldTypeXref;
		END
		ELSE 
		BEGIN
			RAISERROR ('ActionTypeFieldTypeXrefId already exists for Name', 16, 1);
			RETURN
		END	
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @pbiActionTypeFieldTypeXrefId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		THROW
	END CATCH
END
