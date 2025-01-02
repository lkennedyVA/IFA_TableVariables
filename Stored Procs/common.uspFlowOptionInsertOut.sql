USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspFlowOptionInsertOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Description: This procedure will insert a new record
	Tables: [common].[FlowOption]
	History:
		2015-05-07 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [common].[uspFlowOptionInsertOut](
	 @pnvCode NVARCHAR(25)
	,@pnvName NVARCHAR(50)
   ,@pnvDescr NVARCHAR(255)
   ,@piDisplayOrder INT
   ,@piStatusFlag INT
	,@pnvUserName NVARCHAR(100) = 'N/A'
	,@piFlowOptionId INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
   DECLARE @FlowOption table (
		 FlowOptionId int
		,Code nvarchar(25)
		,Name nvarchar(50)
		,Descr nvarchar(255)
		,DisplayOrder int
		,StatusFlag int
		,DateActivated datetime2(7)
		,UserName nvarchar(100)
		);
	DECLARE @iErrorDetailId int
      ,@iCurrentTransactionLevel int
      ,@sSchemaName nvarchar(128) = N'common';
   SET @iCurrentTransactionLevel = @@TRANCOUNT;
   BEGIN TRANSACTION
   BEGIN TRY
      INSERT INTO [common].[FlowOption]
         OUTPUT inserted.FlowOptionId
            ,inserted.Code
            ,inserted.Name
            ,inserted.Descr
            ,inserted.DisplayOrder
            ,inserted.StatusFlag
            ,inserted.DateActivated 
				,inserted.UserName
         INTO @FlowOption
      SELECT @pnvCode
			,@pnvName
         ,@pnvDescr
         ,@piDisplayOrder
         ,@piStatusFlag
         ,SYSDATETIME()
			,@pnvUserName;
   END TRY
   BEGIN CATCH
      IF @@TRANCOUNT > @iCurrentTransactionLevel
         ROLLBACK TRANSACTION;
		EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
		SET @piFlowOptionId = -1 * @iErrorDetailId; --return the errordetailId negative (indicates an error occurred)
   END CATCH;
   IF @@TRANCOUNT > @iCurrentTransactionLevel
   BEGIN
      COMMIT TRANSACTION;
      SELECT @piFlowOptionId = FlowOptionId
      FROM @FlowOption;
	END
END
