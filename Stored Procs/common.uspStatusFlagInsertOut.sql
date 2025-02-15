USE [IFA]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****************************************************************************************
	Name: uspStatusFlagInsertOut
	CreatedBy: Larry Dugger
	Date: 2015-05-07
	Description: This procedure will insert a new record
	Tables: [common].[StatusFlag]
	Procedures: [error].[uspLogErrorDetailInsertOut]
	History:
		2015-05-07 - LBD - Created
*****************************************************************************************/
ALTER PROCEDURE [common].[uspStatusFlagInsertOut](
	 @pnvCode NVARCHAR(25)
	,@pnvName NVARCHAR(50)
   ,@pnvDescr NVARCHAR(255)
	,@pnvUserName NVARCHAR(100) = 'N/A'
   ,@piStatusFlag INT OUTPUT
)
AS
BEGIN
	SET NOCOUNT ON;
   DECLARE @StatusFlag table (
       StatusFlag int
      ,Code nvarchar(25)
      ,Name nvarchar(50)
      ,Descr nvarchar(255)
		,DateActivated datetime2(7)
      ,UserName nvarchar(100)
		);
   DECLARE @iCurrentTransaction int
      ,@iErrorDetailId int
      ,@sSchemaName nvarchar(128);
   SET @sSchemaName = N'common';
   SET @iCurrentTransaction = @@TRANCOUNT;
   BEGIN TRANSACTION
   BEGIN TRY
      INSERT INTO [common].[StatusFlag]
         OUTPUT inserted.StatusFlag
            ,inserted.Code
            ,inserted.Name
            ,inserted.Descr
				,inserted.DateActivated
				,inserted.UserName
         INTO @StatusFlag
      SELECT @pnvCode
         ,@pnvName
         ,@pnvDescr
			,SYSDATETIME()
			,@pnvUserName;
   END TRY
   BEGIN CATCH
      IF @@TRANCOUNT > @iCurrentTransaction
         ROLLBACK TRANSACTION;
      EXEC [error].[uspLogErrorDetailInsertOut] @psSchemaName = @sSchemaName, @piErrorDetailId=@iErrorDetailId OUTPUT;
      SET @piStatusFlag = -1 * @iErrorDetailId;
   END CATCH;
   IF @@TRANCOUNT > @iCurrentTransaction
   BEGIN
      COMMIT TRANSACTION;
      SELECT @piStatusFlag = StatusFlag
      FROM @StatusFlag;
   END
END
