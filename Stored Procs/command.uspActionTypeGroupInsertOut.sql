USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspActionTypeGroupInsertOut
	Created By: Chris Sharp
	Description: This procedure will insert a new ActionTypeGroup record

	Tables: [command].[ActionTypeGroup]

	Procedures: [error].[uspLogErrorDetailUpdateOut]
   
	History:
		2018-03-30 - CBS - Created
*****************************************************************************************/
ALTER PROCEDURE [command].[uspActionTypeGroupInsertOut](
	 @pnvCode NVARCHAR(25)
	,@pnvName NVARCHAR(100)
	,@pnvDescr NVARCHAR(255)
	,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100)
	,@pbiActionTypeGroupId BIGINT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @tblActionTypeGroup TABLE (
		 ActionTypeGroupId bigint
	);
	DECLARE @iErrorDetailId int
		,@sSchemaName sysname = N'command';

	BEGIN TRY
		IF NOT EXISTS (SELECT 'X'
					FROM [command].[ActionTypeGroup] 
					WHERE (Code = @pnvCode
						OR [Name] = @pnvName))
		BEGIN
			INSERT INTO [command].[ActionTypeGroup] (
				 Code
				,[Name]
				,Descr
				,StatusFlag
				,DateActivated
				,UserName
			)
			OUTPUT inserted.ActionTypeGroupId
			INTO @tblActionTypeGroup
			SELECT @pnvCode
				,@pnvName 
				,@pnvDescr 
				,@piStatusFlag
				,SYSDATETIME() AS DateActivated
				,@pnvUserName;

			SELECT @pbiActionTypeGroupId = ActionTypeGroupId 
			FROM @tblActionTypeGroup;
		END
		ELSE 
		BEGIN
			RAISERROR ('ActionTypeGroupId already exists for Code or Name', 16, 1);
			RETURN
		END	
	END TRY
	BEGIN CATCH
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @pbiActionTypeGroupId = -1 * @iErrorDetailId; --return the errordetailid negative (indicates an error occurred)
		THROW
	END CATCH
END
